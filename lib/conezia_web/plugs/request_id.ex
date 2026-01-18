defmodule ConeziaWeb.Plugs.RequestId do
  @moduledoc """
  Plug that ensures every request has a unique request ID.
  Accepts X-Request-ID from the client or generates a new one.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    request_id =
      case get_req_header(conn, "x-request-id") do
        [id | _] when is_binary(id) and byte_size(id) > 0 -> id
        _ -> generate_request_id()
      end

    conn
    |> assign(:request_id, request_id)
    |> put_resp_header("x-request-id", request_id)
  end

  defp generate_request_id do
    UUID.uuid4()
  end
end
