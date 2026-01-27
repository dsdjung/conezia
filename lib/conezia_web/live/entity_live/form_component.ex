defmodule ConeziaWeb.EntityLive.FormComponent do
  @moduledoc """
  LiveComponent for creating and editing entities/connections.
  """
  use ConeziaWeb, :live_component

  alias Conezia.Entities
  alias Conezia.Entities.Relationship

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          {if @action == :new, do: "Add a new connection to your network.", else: "Update connection information."}
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="entity-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input
          field={@form[:type]}
          type="select"
          label="Entity Type"
          options={[{"Person", "person"}, {"Organization", "organization"}]}
          required
        />
        <.input field={@form[:description]} type="textarea" label="Description" />

        <div class="border-t border-gray-200 pt-4 mt-4">
          <h3 class="text-sm font-medium text-gray-900 mb-3">Relationship</h3>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700">Relationship Type</label>
              <select
                name="relationship[type]"
                phx-change="relationship_type_changed"
                phx-target={@myself}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              >
                <option value="">Select type...</option>
                <option :for={{label, value} <- relationship_type_options()} value={value} selected={@relationship_type == value}>
                  {label}
                </option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700">Subtype</label>
              <select
                name="relationship[subtype]"
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
                disabled={@relationship_type == "" or @relationship_type == nil}
              >
                <option value="">Select subtype...</option>
                <option :for={{label, value} <- relationship_subtype_options(@relationship_type)} value={value} selected={@relationship_subtype == value}>
                  {label}
                </option>
              </select>
            </div>
          </div>
          <div class="mt-3">
            <label class="block text-sm font-medium text-gray-700">Custom Label (optional)</label>
            <input
              type="text"
              name="relationship[custom_label]"
              value={@relationship_custom_label}
              placeholder="e.g., College roommate, Team lead"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            />
            <p class="mt-1 text-xs text-gray-500">Add a custom label if the options above don't fit</p>
          </div>
        </div>

        <!-- Profile/Demographics section -->
        <div class="border-t border-gray-200 pt-4 mt-4">
          <h3 class="text-sm font-medium text-gray-900 mb-3">Profile</h3>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:country]}
              type="select"
              label="Country of Residence"
              prompt="Select country..."
              options={country_options()}
            />
            <.input
              field={@form[:timezone]}
              type="select"
              label="Timezone"
              prompt="Select timezone..."
              options={timezone_options()}
            />
          </div>
          <div class="grid grid-cols-2 gap-4 mt-4">
            <.input
              field={@form[:nationality]}
              type="select"
              label="Nationality"
              prompt="Select nationality..."
              options={country_options()}
            />
            <.input
              field={@form[:ethnicity]}
              type="text"
              label="Ethnicity/Background"
              placeholder="e.g., Korean, African American, Mixed"
            />
          </div>
          <div class="grid grid-cols-2 gap-4 mt-4">
            <.input
              field={@form[:preferred_language]}
              type="select"
              label="Preferred Language"
              prompt="Select language..."
              options={language_options()}
            />
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Languages Spoken</label>
              <p class="text-xs text-gray-500 mb-2">Hold Ctrl/Cmd to select multiple</p>
              <select
                name="entity[languages][]"
                multiple
                size="4"
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
              >
                <option :for={{label, value} <- language_options()} value={value} selected={value in (@form[:languages].value || [])}>
                  {label}
                </option>
              </select>
            </div>
          </div>
        </div>

        <:actions>
          <.button phx-disable-with="Saving...">Save Connection</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{entity: entity} = assigns, socket) do
    changeset = Entities.change_entity(entity)
    relationship = Map.get(assigns, :relationship)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:relationship_type, relationship && relationship.type)
     |> assign(:relationship_subtype, relationship && relationship.subtype)
     |> assign(:relationship_custom_label, relationship && relationship.custom_label)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"entity" => entity_params}, socket) do
    changeset =
      socket.assigns.entity
      |> Entities.change_entity(entity_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("relationship_type_changed", %{"relationship" => %{"type" => type}}, socket) do
    {:noreply,
     socket
     |> assign(:relationship_type, type)
     |> assign(:relationship_subtype, nil)}
  end

  def handle_event("save", %{"entity" => entity_params} = params, socket) do
    relationship_params = Map.get(params, "relationship", %{})
    save_entity(socket, socket.assigns.action, entity_params, relationship_params)
  end

  defp save_entity(socket, :edit, entity_params, relationship_params) do
    case Entities.update_entity(socket.assigns.entity, entity_params) do
      {:ok, entity} ->
        save_or_update_relationship(socket, entity, relationship_params)
        notify_parent({:saved, entity})

        {:noreply,
         socket
         |> put_flash(:info, "Connection updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_entity(socket, :new, entity_params, relationship_params) do
    entity_params = Map.put(entity_params, "owner_id", socket.assigns.current_user.id)

    case Entities.create_entity(entity_params) do
      {:ok, entity} ->
        save_or_update_relationship(socket, entity, relationship_params)
        notify_parent({:saved, entity})

        {:noreply,
         socket
         |> put_flash(:info, "Connection created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_or_update_relationship(socket, entity, params) do
    user = socket.assigns.current_user
    type = params["type"]

    if type && type != "" do
      case Entities.get_relationship_for_entity(user.id, entity.id) do
        nil ->
          Entities.create_relationship(%{
            user_id: user.id,
            entity_id: entity.id,
            type: type,
            subtype: params["subtype"],
            custom_label: params["custom_label"],
            status: "active"
          })

        existing ->
          Entities.update_relationship(existing, %{
            type: type,
            subtype: params["subtype"],
            custom_label: params["custom_label"]
          })
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "entity"))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp relationship_type_options do
    [
      {"Family", "family"},
      {"Friend", "friend"},
      {"Colleague", "colleague"},
      {"Professional", "professional"},
      {"Community", "community"},
      {"Service Provider", "service"},
      {"Acquaintance", "acquaintance"},
      {"Other", "other"}
    ]
  end

  defp relationship_subtype_options(nil), do: []
  defp relationship_subtype_options(""), do: []
  defp relationship_subtype_options(type) do
    Relationship.subtypes_for_type(type)
    |> Enum.map(fn subtype ->
      {humanize_subtype(subtype), subtype}
    end)
  end

  defp humanize_subtype(subtype) when is_binary(subtype) do
    subtype
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp country_options do
    [
      {"United States", "US"},
      {"United Kingdom", "GB"},
      {"Canada", "CA"},
      {"Australia", "AU"},
      {"Germany", "DE"},
      {"France", "FR"},
      {"Japan", "JP"},
      {"South Korea", "KR"},
      {"China", "CN"},
      {"India", "IN"},
      {"Brazil", "BR"},
      {"Mexico", "MX"},
      {"Spain", "ES"},
      {"Italy", "IT"},
      {"Netherlands", "NL"},
      {"Sweden", "SE"},
      {"Switzerland", "CH"},
      {"Singapore", "SG"},
      {"Hong Kong", "HK"},
      {"Taiwan", "TW"},
      {"New Zealand", "NZ"},
      {"Ireland", "IE"},
      {"Israel", "IL"},
      {"South Africa", "ZA"},
      {"United Arab Emirates", "AE"},
      {"Argentina", "AR"},
      {"Chile", "CL"},
      {"Colombia", "CO"},
      {"Philippines", "PH"},
      {"Thailand", "TH"},
      {"Vietnam", "VN"},
      {"Indonesia", "ID"},
      {"Malaysia", "MY"},
      {"Poland", "PL"},
      {"Portugal", "PT"},
      {"Belgium", "BE"},
      {"Austria", "AT"},
      {"Norway", "NO"},
      {"Denmark", "DK"},
      {"Finland", "FI"}
    ]
    |> Enum.sort_by(fn {label, _} -> label end)
  end

  defp timezone_options do
    [
      {"Pacific Time (US)", "America/Los_Angeles"},
      {"Mountain Time (US)", "America/Denver"},
      {"Central Time (US)", "America/Chicago"},
      {"Eastern Time (US)", "America/New_York"},
      {"London (GMT/BST)", "Europe/London"},
      {"Paris (CET/CEST)", "Europe/Paris"},
      {"Berlin (CET/CEST)", "Europe/Berlin"},
      {"Tokyo (JST)", "Asia/Tokyo"},
      {"Seoul (KST)", "Asia/Seoul"},
      {"Shanghai (CST)", "Asia/Shanghai"},
      {"Hong Kong (HKT)", "Asia/Hong_Kong"},
      {"Singapore (SGT)", "Asia/Singapore"},
      {"Sydney (AEST/AEDT)", "Australia/Sydney"},
      {"Auckland (NZST/NZDT)", "Pacific/Auckland"},
      {"Mumbai (IST)", "Asia/Kolkata"},
      {"Dubai (GST)", "Asia/Dubai"},
      {"São Paulo (BRT)", "America/Sao_Paulo"},
      {"Toronto (EST/EDT)", "America/Toronto"},
      {"Vancouver (PST/PDT)", "America/Vancouver"},
      {"UTC", "Etc/UTC"}
    ]
  end

  defp language_options do
    [
      {"English", "en"},
      {"Spanish", "es"},
      {"French", "fr"},
      {"German", "de"},
      {"Italian", "it"},
      {"Portuguese", "pt"},
      {"Chinese (Simplified)", "zh-Hans"},
      {"Chinese (Traditional)", "zh-Hant"},
      {"Japanese", "ja"},
      {"Korean", "ko"},
      {"Arabic", "ar"},
      {"Hindi", "hi"},
      {"Russian", "ru"},
      {"Dutch", "nl"},
      {"Swedish", "sv"},
      {"Norwegian", "no"},
      {"Danish", "da"},
      {"Finnish", "fi"},
      {"Polish", "pl"},
      {"Turkish", "tr"},
      {"Thai", "th"},
      {"Vietnamese", "vi"},
      {"Indonesian", "id"},
      {"Malay", "ms"},
      {"Tagalog", "tl"},
      {"Hebrew", "he"},
      {"Greek", "el"},
      {"Czech", "cs"},
      {"Hungarian", "hu"},
      {"Romanian", "ro"}
    ]
    |> Enum.sort_by(fn {label, _} -> label end)
  end
end
