defmodule Conezia.Validators.IdentifierValidator do
  @moduledoc """
  Validation rules for entity identifiers (phone, email, SSN, etc.).
  """
  import Ecto.Changeset

  @identifier_types ~w(phone email ssn government_id account_number social_handle website)
  @sensitive_types ~w(ssn government_id account_number)

  # E.164 phone format: +[country code][number], 7-15 digits total
  @phone_regex ~r/^\+[1-9]\d{6,14}$/

  # Standard email regex (RFC 5322 simplified)
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  # US SSN format: XXX-XX-XXXX
  @ssn_regex ~r/^\d{3}-\d{2}-\d{4}$/

  # Social handle: alphanumeric with underscore, optionally prefixed with @
  @social_handle_regex ~r/^@?[a-zA-Z0-9_]{1,50}$/

  def validate_type(changeset) do
    changeset
    |> validate_required([:type])
    |> validate_inclusion(:type, @identifier_types,
        message: "must be one of: #{Enum.join(@identifier_types, ", ")}")
  end

  def validate_value(changeset) do
    changeset
    |> validate_required([:value])
    |> validate_value_by_type()
  end

  defp validate_value_by_type(changeset) do
    type = get_field(changeset, :type)
    value = get_change(changeset, :value)

    if value && type do
      case type do
        "phone" -> validate_phone_value(changeset, value)
        "email" -> validate_email_value(changeset, value)
        "ssn" -> validate_ssn_value(changeset, value)
        "government_id" -> validate_government_id_value(changeset, value)
        "account_number" -> validate_account_number_value(changeset, value)
        "social_handle" -> validate_social_handle_value(changeset, value)
        "website" -> validate_website_value(changeset, value)
        _ -> changeset
      end
    else
      changeset
    end
  end

  defp validate_phone_value(changeset, value) do
    # Normalize phone: remove spaces, dashes, parentheses
    normalized = String.replace(value, ~r/[\s\-\(\)]+/, "")

    if Regex.match?(@phone_regex, normalized) do
      put_change(changeset, :value, normalized)
    else
      add_error(changeset, :value,
        "must be in E.164 format (e.g., +12025551234)")
    end
  end

  defp validate_email_value(changeset, value) do
    normalized = String.downcase(String.trim(value))

    cond do
      String.length(normalized) > 254 ->
        add_error(changeset, :value, "must be at most 254 characters")
      !Regex.match?(@email_regex, normalized) ->
        add_error(changeset, :value, "must be a valid email address")
      true ->
        put_change(changeset, :value, normalized)
    end
  end

  defp validate_ssn_value(changeset, value) do
    if Regex.match?(@ssn_regex, value) do
      # Additional validation: check for invalid SSNs
      [area, group, serial] = String.split(value, "-")

      cond do
        area == "000" or area == "666" or String.starts_with?(area, "9") ->
          add_error(changeset, :value, "contains invalid area number")
        group == "00" ->
          add_error(changeset, :value, "contains invalid group number")
        serial == "0000" ->
          add_error(changeset, :value, "contains invalid serial number")
        true ->
          changeset
      end
    else
      add_error(changeset, :value, "must be in format XXX-XX-XXXX")
    end
  end

  defp validate_government_id_value(changeset, value) do
    # Basic validation - alphanumeric with some special chars
    if String.length(value) > 0 and String.length(value) <= 50 and
       Regex.match?(~r/^[a-zA-Z0-9\-\s]+$/, value) do
      changeset
    else
      add_error(changeset, :value,
        "must be 1-50 characters, alphanumeric with hyphens and spaces only")
    end
  end

  defp validate_account_number_value(changeset, value) do
    # Basic validation - alphanumeric
    if String.length(value) > 0 and String.length(value) <= 50 and
       Regex.match?(~r/^[a-zA-Z0-9\-]+$/, value) do
      changeset
    else
      add_error(changeset, :value,
        "must be 1-50 characters, alphanumeric with hyphens only")
    end
  end

  defp validate_social_handle_value(changeset, value) do
    normalized = if String.starts_with?(value, "@"), do: value, else: "@#{value}"

    if Regex.match?(@social_handle_regex, String.slice(normalized, 1..-1//1)) do
      put_change(changeset, :value, normalized)
    else
      add_error(changeset, :value,
        "must be 1-50 alphanumeric characters or underscores")
    end
  end

  defp validate_website_value(changeset, value) do
    # Add protocol if missing
    normalized = if String.starts_with?(value, "http"),
      do: value,
      else: "https://#{value}"

    case URI.parse(normalized) do
      %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if String.length(normalized) <= 2048 do
          put_change(changeset, :value, normalized)
        else
          add_error(changeset, :value, "must be at most 2048 characters")
        end
      _ ->
        add_error(changeset, :value, "must be a valid URL")
    end
  end

  def validate_label(changeset) do
    changeset
    |> validate_length(:label, max: 64)
    |> validate_format(:label, ~r/^[\p{L}\p{N}\s\-]+$/u,
        message: "can only contain letters, numbers, spaces, and hyphens")
  end

  def sensitive_type?(type), do: type in @sensitive_types
  def identifier_types, do: @identifier_types
  def sensitive_types, do: @sensitive_types
end
