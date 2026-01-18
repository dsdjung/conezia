defmodule ConeziaWeb.ErrorHelpers do
  @moduledoc """
  Helpers for returning RFC 7807 compliant error responses.
  """

  @base_url "https://api.conezia.com/errors"

  @doc """
  Builds a validation error response from changeset errors.
  """
  def validation_errors(changeset, instance \\ nil) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    field_errors =
      Enum.flat_map(errors, fn {field, messages} ->
        Enum.map(messages, fn message ->
          %{
            field: to_string(field),
            code: error_code_from_message(message),
            message: message
          }
        end)
      end)

    error_response(:validation_error, "Validation Error", 422,
      "The request body contains invalid data.",
      instance: instance,
      errors: field_errors
    )
  end

  @doc """
  Builds a not found error response.
  """
  def not_found(resource_type, id \\ nil, instance \\ nil) do
    detail =
      if id do
        "#{String.capitalize(resource_type)} with ID '#{id}' not found."
      else
        "#{String.capitalize(resource_type)} not found."
      end

    error_response(:not_found, "Not Found", 404, detail, instance: instance)
  end

  @doc """
  Builds an unauthorized error response.
  """
  def unauthorized(detail \\ "Authentication required.", instance \\ nil) do
    error_response(:unauthorized, "Unauthorized", 401, detail, instance: instance)
  end

  @doc """
  Builds a forbidden error response.
  """
  def forbidden(detail \\ "You do not have permission to perform this action.", instance \\ nil) do
    error_response(:forbidden, "Forbidden", 403, detail, instance: instance)
  end

  @doc """
  Builds a conflict error response.
  """
  def conflict(detail, instance \\ nil) do
    error_response(:conflict, "Conflict", 409, detail, instance: instance)
  end

  @doc """
  Builds a bad request error response.
  """
  def bad_request(detail, instance \\ nil) do
    error_response(:bad_request, "Bad Request", 400, detail, instance: instance)
  end

  @doc """
  Builds an internal server error response.
  """
  def internal_error(instance \\ nil) do
    error_response(:internal_error, "Internal Server Error", 500,
      "An unexpected error occurred. Please try again later.",
      instance: instance
    )
  end

  @doc """
  Builds a generic error response.
  """
  def error_response(type, title, status, detail, opts \\ []) do
    base = %{
      error: %{
        type: "#{@base_url}/#{type_to_string(type)}",
        title: title,
        status: status,
        detail: detail
      }
    }

    base =
      if instance = Keyword.get(opts, :instance) do
        put_in(base, [:error, :instance], instance)
      else
        base
      end

    if errors = Keyword.get(opts, :errors) do
      put_in(base, [:error, :errors], errors)
    else
      base
    end
  end

  defp type_to_string(type) when is_atom(type), do: type |> to_string() |> String.replace("_", "-")
  defp type_to_string(type), do: type

  defp error_code_from_message(message) do
    cond do
      String.contains?(message, "required") -> "required"
      String.contains?(message, "blank") -> "required"
      String.contains?(message, "format") -> "invalid_format"
      String.contains?(message, "valid") -> "invalid"
      String.contains?(message, "length") -> "invalid_length"
      String.contains?(message, "already") -> "duplicate"
      String.contains?(message, "exist") -> "not_found"
      true -> "invalid"
    end
  end
end
