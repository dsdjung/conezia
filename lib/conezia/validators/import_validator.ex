defmodule Conezia.Validators.ImportValidator do
  @moduledoc """
  Validation rules for import operations.
  """
  import Ecto.Changeset

  @sources ~w(google csv vcard linkedin icloud outlook)
  @max_file_size 10 * 1024 * 1024  # 10 MB for import files
  @max_records_per_import 10_000

  def validate_source(changeset) do
    changeset
    |> validate_required([:source])
    |> validate_inclusion(:source, @sources,
        message: "must be one of: #{Enum.join(@sources, ", ")}")
  end

  def validate_file(file_path, source) do
    cond do
      !File.exists?(file_path) ->
        {:error, "file not found"}
      File.stat!(file_path).size > @max_file_size ->
        {:error, "file exceeds maximum size of #{div(@max_file_size, 1024 * 1024)} MB"}
      true ->
        validate_file_content(file_path, source)
    end
  end

  defp validate_file_content(file_path, "csv") do
    case File.read(file_path) do
      {:ok, content} ->
        lines = String.split(content, ~r/\r?\n/, trim: true)
        row_count = length(lines)

        cond do
          row_count > @max_records_per_import + 1 ->
            {:error, "file contains more than #{@max_records_per_import} records"}
          row_count > 1 ->
            {:ok, row_count - 1}  # Subtract header row
          true ->
            {:error, "file must contain at least one data row"}
        end
      {:error, _} ->
        {:error, "could not read file"}
    end
  end

  defp validate_file_content(file_path, "vcard") do
    case File.read(file_path) do
      {:ok, content} ->
        vcard_count = content
          |> String.split("BEGIN:VCARD")
          |> length()
          |> Kernel.-(1)

        cond do
          vcard_count == 0 ->
            {:error, "no valid vCard entries found"}
          vcard_count > @max_records_per_import ->
            {:error, "file contains more than #{@max_records_per_import} contacts"}
          true ->
            {:ok, vcard_count}
        end
      {:error, _} ->
        {:error, "could not read file"}
    end
  end

  defp validate_file_content(_file_path, _source) do
    {:ok, :unknown}
  end

  def validate_field_mapping(mapping, source) do
    required_fields = case source do
      "csv" -> ["name"]
      "vcard" -> []  # vCard has structured fields
      _ -> []
    end

    mapped_fields = Map.values(mapping)
    missing = required_fields -- mapped_fields

    if missing == [] do
      :ok
    else
      {:error, "missing required field mappings: #{Enum.join(missing, ", ")}"}
    end
  end

  def sources, do: @sources
  def max_file_size, do: @max_file_size
  def max_records_per_import, do: @max_records_per_import
end
