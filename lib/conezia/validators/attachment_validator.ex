defmodule Conezia.Validators.AttachmentValidator do
  @moduledoc """
  Validation rules for file attachments.
  """
  import Ecto.Changeset

  @max_file_size 50 * 1024 * 1024  # 50 MB
  @max_filename_length 255

  @allowed_mime_types %{
    # Images
    "image/jpeg" => [".jpg", ".jpeg"],
    "image/png" => [".png"],
    "image/gif" => [".gif"],
    "image/webp" => [".webp"],
    # Documents
    "application/pdf" => [".pdf"],
    "text/plain" => [".txt"],
    "text/csv" => [".csv"],
    # Office documents
    "application/msword" => [".doc"],
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => [".docx"],
    "application/vnd.ms-excel" => [".xls"],
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => [".xlsx"],
    # Archives
    "application/zip" => [".zip"]
  }

  def validate_filename(changeset) do
    changeset
    |> validate_required([:filename])
    |> validate_length(:filename, min: 1, max: @max_filename_length)
    |> validate_filename_safety()
  end

  defp validate_filename_safety(changeset) do
    validate_change(changeset, :filename, fn :filename, filename ->
      cond do
        # Prevent directory traversal
        String.contains?(filename, ["../", "..\\"]) ->
          [filename: "cannot contain directory traversal sequences"]
        # Prevent null bytes
        String.contains?(filename, <<0>>) ->
          [filename: "cannot contain null bytes"]
        # Check for valid characters
        !Regex.match?(~r/^[\w\-\. ]+$/u, filename) ->
          [filename: "contains invalid characters"]
        true ->
          []
      end
    end)
  end

  def validate_mime_type(changeset) do
    changeset
    |> validate_required([:mime_type])
    |> validate_inclusion(:mime_type, Map.keys(@allowed_mime_types),
        message: "file type not allowed")
    |> validate_extension_matches_mime()
  end

  defp validate_extension_matches_mime(changeset) do
    mime_type = get_field(changeset, :mime_type)
    filename = get_field(changeset, :filename)

    if mime_type && filename do
      allowed_extensions = Map.get(@allowed_mime_types, mime_type, [])
      extension = Path.extname(filename) |> String.downcase()

      if extension in allowed_extensions do
        changeset
      else
        add_error(changeset, :filename,
          "extension does not match mime type #{mime_type}")
      end
    else
      changeset
    end
  end

  def validate_size(changeset) do
    changeset
    |> validate_required([:size_bytes])
    |> validate_number(:size_bytes,
        greater_than: 0,
        less_than_or_equal_to: @max_file_size,
        message: "must be between 1 byte and #{div(@max_file_size, 1024 * 1024)} MB")
  end

  def validate_parent_association(changeset) do
    entity_id = get_field(changeset, :entity_id)
    interaction_id = get_field(changeset, :interaction_id)
    communication_id = get_field(changeset, :communication_id)

    if entity_id || interaction_id || communication_id do
      changeset
    else
      add_error(changeset, :entity_id,
        "at least one of entity_id, interaction_id, or communication_id is required")
    end
  end

  def allowed_mime_types, do: @allowed_mime_types
  def max_file_size, do: @max_file_size
  def max_filename_length, do: @max_filename_length
end
