defmodule ConeziaWeb.ErrorHTML do
  @moduledoc """
  Error page rendering for HTML responses.
  """
  use ConeziaWeb, :html

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
