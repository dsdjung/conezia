defmodule Conezia.Encrypted do
  @moduledoc """
  Custom Ecto types for encrypted fields.

  These types automatically encrypt data before saving to the database
  and decrypt it when loading. Uses AES-256-GCM encryption via Conezia.Vault.

  ## Usage

      schema "my_table" do
        field :sensitive_data, Conezia.Encrypted.Binary
        field :api_token, Conezia.Encrypted.Binary
      end
  """
end

defmodule Conezia.Encrypted.Binary do
  @moduledoc """
  Ecto type for encrypted binary/string fields.

  Data is encrypted with AES-256-GCM before storage and decrypted on load.
  The encrypted value is stored as a base64-encoded binary containing
  the IV, authentication tag, and ciphertext.

  ## Example

      schema "tokens" do
        field :access_token, Conezia.Encrypted.Binary
        field :refresh_token, Conezia.Encrypted.Binary
      end
  """
  use Ecto.Type

  alias Conezia.Vault

  @impl true
  def type, do: :binary

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(""), do: {:ok, ""}
  def dump(value) when is_binary(value) do
    encrypted = Vault.encrypt(value)
    {:ok, encrypted}
  end
  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}
  def load(""), do: {:ok, ""}
  def load(value) when is_binary(value) do
    case Vault.decrypt(value) do
      {:ok, decrypted} -> {:ok, decrypted}
      {:error, _reason} -> {:ok, nil}
    end
  end
  def load(_), do: :error

  @impl true
  def equal?(nil, nil), do: true
  def equal?(a, b), do: a == b

  @impl true
  def embed_as(_), do: :dump
end

defmodule Conezia.Encrypted.Map do
  @moduledoc """
  Ecto type for encrypted map/JSON fields.

  Data is JSON-encoded, then encrypted with AES-256-GCM before storage.
  On load, data is decrypted and JSON-decoded back to a map.

  ## Example

      schema "settings" do
        field :user_preferences, Conezia.Encrypted.Map
      end
  """
  use Ecto.Type

  alias Conezia.Vault

  @impl true
  def type, do: :binary

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_map(value), do: {:ok, value}
  def cast(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} -> {:ok, map}
      _ -> :error
    end
  end
  def cast(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(value) when is_map(value) do
    json = Jason.encode!(value)
    encrypted = Vault.encrypt(json)
    {:ok, encrypted}
  end
  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}
  def load(""), do: {:ok, %{}}
  def load(value) when is_binary(value) do
    case Vault.decrypt(value) do
      {:ok, nil} -> {:ok, nil}
      {:ok, ""} -> {:ok, %{}}
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, map} -> {:ok, map}
          _ -> {:ok, nil}
        end
      {:error, _reason} -> {:ok, nil}
    end
  end
  def load(_), do: :error

  @impl true
  def equal?(nil, nil), do: true
  def equal?(a, b) when is_map(a) and is_map(b), do: a == b
  def equal?(_, _), do: false

  @impl true
  def embed_as(_), do: :dump
end
