defmodule Conezia.Workers.ImportWorker do
  @moduledoc """
  Oban worker for processing contact import jobs.
  """
  use Oban.Worker, queue: :imports, max_attempts: 3

  alias Conezia.Imports
  alias Conezia.Imports.ImportJob
  alias Conezia.Entities
  alias Conezia.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"import_job_id" => import_job_id}}) do
    case Repo.get(ImportJob, import_job_id) do
      nil ->
        {:error, :import_job_not_found}

      %ImportJob{status: "completed"} ->
        # Already completed
        :ok

      %ImportJob{status: "failed"} ->
        # Already failed, don't retry
        :ok

      import_job ->
        process_import(import_job)
    end
  end

  defp process_import(import_job) do
    # Mark as processing
    {:ok, import_job} = Imports.start_import(import_job)

    try do
      result = case import_job.source do
        "csv" -> process_csv_import(import_job)
        "vcard" -> process_vcard_import(import_job)
        "google" -> process_google_import(import_job)
        _ -> {:error, "Unsupported import source: #{import_job.source}"}
      end

      case result do
        {:ok, stats} ->
          Imports.complete_import(import_job, stats)
          :ok

        {:error, errors} when is_list(errors) ->
          Imports.fail_import(import_job, errors)
          {:error, errors}

        {:error, error} ->
          Imports.fail_import(import_job, [%{message: to_string(error)}])
          {:error, error}
      end
    rescue
      e ->
        Imports.fail_import(import_job, [%{message: Exception.message(e)}])
        {:error, e}
    end
  end

  defp process_csv_import(import_job) do
    case File.read(import_job.file_path) do
      {:ok, content} ->
        lines = String.split(content, ~r/\r?\n/, trim: true)
        [header | rows] = lines

        columns = String.split(header, ",") |> Enum.map(&String.trim/1)
        name_idx = Enum.find_index(columns, &(&1 in ["name", "Name", "full_name", "Full Name"]))
        email_idx = Enum.find_index(columns, &(&1 in ["email", "Email", "email_address"]))
        phone_idx = Enum.find_index(columns, &(&1 in ["phone", "Phone", "phone_number"]))
        type_idx = Enum.find_index(columns, &(&1 in ["type", "Type"]))

        stats = Enum.reduce(rows, %{created: 0, skipped: 0, errors: []}, fn row, acc ->
          fields = String.split(row, ",") |> Enum.map(&String.trim/1)

          name = if name_idx, do: Enum.at(fields, name_idx), else: nil
          email = if email_idx, do: Enum.at(fields, email_idx), else: nil
          phone = if phone_idx, do: Enum.at(fields, phone_idx), else: nil
          type = if type_idx, do: Enum.at(fields, type_idx) || "person", else: "person"

          if name && String.length(name) > 0 do
            case create_entity_from_import(import_job.user_id, name, type, email, phone) do
              {:ok, _entity} -> %{acc | created: acc.created + 1}
              {:error, _} -> %{acc | skipped: acc.skipped + 1}
            end
          else
            %{acc | skipped: acc.skipped + 1}
          end
        end)

        {:ok, %{
          total_records: length(rows),
          processed_records: length(rows),
          created_records: stats.created,
          skipped_records: stats.skipped,
          merged_records: 0
        }}

      {:error, reason} ->
        {:error, [%{message: "Failed to read file: #{reason}"}]}
    end
  end

  defp process_vcard_import(import_job) do
    case File.read(import_job.file_path) do
      {:ok, content} ->
        vcards = String.split(content, "BEGIN:VCARD") |> Enum.drop(1)

        stats = Enum.reduce(vcards, %{created: 0, skipped: 0}, fn vcard, acc ->
          case parse_vcard(vcard) do
            {:ok, %{name: name} = data} when is_binary(name) and name != "" ->
              case create_entity_from_import(import_job.user_id, name, "person", data[:email], data[:phone]) do
                {:ok, _} -> %{acc | created: acc.created + 1}
                {:error, _} -> %{acc | skipped: acc.skipped + 1}
              end
            _ ->
              %{acc | skipped: acc.skipped + 1}
          end
        end)

        {:ok, %{
          total_records: length(vcards),
          processed_records: length(vcards),
          created_records: stats.created,
          skipped_records: stats.skipped,
          merged_records: 0
        }}

      {:error, reason} ->
        {:error, [%{message: "Failed to read file: #{reason}"}]}
    end
  end

  defp parse_vcard(vcard) do
    lines = String.split(vcard, ~r/\r?\n/)

    data = Enum.reduce(lines, %{}, fn line, acc ->
      cond do
        String.starts_with?(line, "FN:") ->
          Map.put(acc, :name, String.trim_leading(line, "FN:"))
        String.starts_with?(line, "EMAIL") ->
          email = line |> String.split(":") |> List.last() |> String.trim()
          Map.put(acc, :email, email)
        String.starts_with?(line, "TEL") ->
          phone = line |> String.split(":") |> List.last() |> String.trim()
          Map.put(acc, :phone, phone)
        true ->
          acc
      end
    end)

    if data[:name], do: {:ok, data}, else: {:error, :no_name}
  end

  defp process_google_import(_import_job) do
    # Google import would require OAuth and API calls
    {:error, "Google import not yet implemented"}
  end

  defp create_entity_from_import(user_id, name, type, email, phone) do
    attrs = %{
      "name" => name,
      "type" => type,
      "owner_id" => user_id
    }

    case Entities.create_entity(attrs) do
      {:ok, entity} ->
        # Add identifiers if provided
        if email && String.length(email) > 0 do
          Entities.create_identifier(%{
            "entity_id" => entity.id,
            "type" => "email",
            "value" => email,
            "is_primary" => true
          })
        end

        if phone && String.length(phone) > 0 do
          Entities.create_identifier(%{
            "entity_id" => entity.id,
            "type" => "phone",
            "value" => phone,
            "is_primary" => email == nil
          })
        end

        {:ok, entity}

      error ->
        error
    end
  end

  @doc """
  Enqueue an import job for processing.
  """
  def enqueue(import_job_id) do
    %{import_job_id: import_job_id}
    |> new()
    |> Oban.insert()
  end
end
