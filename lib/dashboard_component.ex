defmodule Kanta.POWriter.Plugin.DashboardComponent do
  @moduledoc """
  Phoenix LiveComponent for Kanta dashboard
  """

  require Logger

  use Phoenix.LiveComponent

  alias Kanta.Translations

  @default_priv "priv/gettext"

  def render(assigns) do
    ~H"""
      <div class="col-span-2">
        <div class="bg-white dark:bg-stone-900 overflow-hidden shadow rounded-lg">
          <div class="flex flex-col items-center justify-center px-4 py-5 sm:p-6">
            <div class="text-3xl font-bold text-primary dark:text-accent-light">PO file extraction</div>
            <form phx-submit="extract-2" phx-target={@myself}>
              <select name="locale">
                <option :for={locale <- @locales} value={locale.iso639_code}><%= locale.name %></option>
              </select>
              <select name="domain">
                <option :for={domain <- @domains} value={domain.name}><%= domain.name %></option>
              </select>
              <button type="submit" class="bg-white">Extract</button>
            </form>
          </div>
        </div>
      </div>
    """
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      # TODO: deal with paginatio
      |> assign(:domains, Translations.list_domains().entries)
      |> assign(:locales, Translations.list_locales().entries)

    {:ok, socket}
  end

  def handle_event("extract-2", %{"domain" => domain, "locale" => locale}, socket) do
    path = po_file_path(domain, locale)

    domain_id =
      (socket.assigns.domains |> Enum.filter(fn d -> d.name == domain end) |> List.first()).id
      |> IO.inspect(label: "DOMAIN_ID")

    path
    |> parse_po_file()
    |> translate_messages({domain, domain_id}, locale)
    |> write_messages(elem(path, 1))

    {:noreply, socket}
  end

  defp translate_messages({:ok, %Expo.Messages{} = messages}, domain, locale) do
    new_messages =
      messages.messages
      |> Stream.map(&translate_message(&1, domain, locale))
      |> Enum.to_list()

    {:ok, %Expo.Messages{messages | messages: new_messages}}
  end

  defp translate_messages(rest, _, _), do: rest

  defp translate_message(%Expo.Message.Singular{} = msg, {domain, domain_id}, locale) do
    # not sure why expo has ["my_message_id"] instead of "my_message_id"
    # maybe find for each msgid ???
    # how to resolve conflicts then ???
    msgid = msg.msgid |> List.first()

    {:ok, kanta_msg} =
      Translations.get_message(
        filter: [msgid: msgid, domain_id: domain_id],
        preloads: [singular_translations: :locale]
      )

    translations = kanta_msg.singular_translations

    new_msgstr =
      translations
      |> Enum.filter(fn translation -> translation.locale.iso639_code == locale end)
      |> Enum.map(&(&1.translated_text || &1.original_text || ""))

    %Expo.Message.Singular{msg | msgstr: new_msgstr}
  end

  # TODO: Plural messages
  defp translate_message(rest, _, _), do: rest

  defp write_messages({:ok, %Expo.Messages{} = msgs}, path) do
    iodata = Expo.PO.compose(msgs)
    File.write!(path, iodata)
    {:ok, msgs}
  end

  defp write_messages(rest, path), do: rest

  defp po_file_path(domain, locale) do
    priv = Application.get_env(:kanta, :priv, @default_priv)
    path = Path.join(priv, "#{locale}/LC_MESSAGES/#{domain}.po")

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "Path #{inspect(path)} doesn't exist"}
    end
  end

  defp parse_po_file({:ok, path}), do: Expo.PO.parse_file(path)
  defp parse_po_file(rest), do: rest
end
