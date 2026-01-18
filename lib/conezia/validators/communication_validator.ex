defmodule Conezia.Validators.CommunicationValidator do
  @moduledoc """
  Validation rules for communication data.
  """
  import Ecto.Changeset

  @channels ~w(internal email sms whatsapp telegram phone)
  @directions ~w(inbound outbound)
  @max_content_length 100_000
  @max_attachments 10

  def validate_channel(changeset) do
    changeset
    |> validate_required([:channel])
    |> validate_inclusion(:channel, @channels,
        message: "must be one of: #{Enum.join(@channels, ", ")}")
  end

  def validate_direction(changeset) do
    changeset
    |> validate_required([:direction])
    |> validate_inclusion(:direction, @directions,
        message: "must be one of: #{Enum.join(@directions, ", ")}")
  end

  def validate_content(changeset) do
    changeset
    |> validate_required([:content])
    |> validate_length(:content,
        min: 1,
        max: @max_content_length,
        message: "must be between 1 and #{@max_content_length} characters")
    |> validate_not_blank(:content)
  end

  def validate_attachments(changeset) do
    validate_change(changeset, :attachments, fn :attachments, attachments ->
      cond do
        length(attachments) > @max_attachments ->
          [attachments: "cannot have more than #{@max_attachments} attachments"]
        true ->
          validate_each_attachment(attachments)
      end
    end)
  end

  defp validate_each_attachment(attachments) do
    attachments
    |> Enum.with_index()
    |> Enum.flat_map(fn {attachment, index} ->
      errors = []

      errors = if !Map.has_key?(attachment, "id"),
        do: [{:attachments, "attachment #{index + 1} must have an id"} | errors],
        else: errors

      errors = if !Map.has_key?(attachment, "filename"),
        do: [{:attachments, "attachment #{index + 1} must have a filename"} | errors],
        else: errors

      errors = if !Map.has_key?(attachment, "mime_type"),
        do: [{:attachments, "attachment #{index + 1} must have a mime_type"} | errors],
        else: errors

      errors
    end)
  end

  def validate_sent_at(changeset) do
    validate_change(changeset, :sent_at, fn :sent_at, sent_at ->
      # Allow up to 1 hour in the future (for scheduled sends)
      max_future = DateTime.add(DateTime.utc_now(), 3600, :second)

      if DateTime.compare(sent_at, max_future) == :gt do
        [sent_at: "cannot be more than 1 hour in the future"]
      else
        []
      end
    end)
  end

  defp validate_not_blank(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      if String.trim(value) == "" do
        [{field, "cannot be blank"}]
      else
        []
      end
    end)
  end

  def channels, do: @channels
  def directions, do: @directions
  def max_content_length, do: @max_content_length
  def max_attachments, do: @max_attachments
end
