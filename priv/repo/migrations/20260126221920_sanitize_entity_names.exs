defmodule Conezia.Repo.Migrations.SanitizeEntityNames do
  use Ecto.Migration

  @doc """
  Data migration to clean up entity names that have leading/trailing
  quotes or angle brackets.

  This fixes names like:
  - "Poets&Quants For Undergrads" -> Poets&Quants For Undergrads
  - Robert" -> Robert
  - <John Smith> -> John Smith
  - "Company Name -> Company Name
  """

  def up do
    # Remove leading double quotes
    execute """
    UPDATE entities
    SET name = LTRIM(name, '"'),
        updated_at = NOW()
    WHERE name LIKE '"%'
    """

    # Remove trailing double quotes
    execute """
    UPDATE entities
    SET name = RTRIM(name, '"'),
        updated_at = NOW()
    WHERE name LIKE '%"'
    """

    # Remove leading single quotes
    execute """
    UPDATE entities
    SET name = LTRIM(name, ''''),
        updated_at = NOW()
    WHERE name LIKE '''%'
    """

    # Remove trailing single quotes
    execute """
    UPDATE entities
    SET name = RTRIM(name, ''''),
        updated_at = NOW()
    WHERE name LIKE '%'''
    """

    # Remove leading angle brackets
    execute """
    UPDATE entities
    SET name = LTRIM(name, '<'),
        updated_at = NOW()
    WHERE name LIKE '<%'
    """

    # Remove trailing angle brackets
    execute """
    UPDATE entities
    SET name = RTRIM(name, '>'),
        updated_at = NOW()
    WHERE name LIKE '%>'
    """

    # Final trim to remove any whitespace left over
    execute """
    UPDATE entities
    SET name = TRIM(name),
        updated_at = NOW()
    WHERE name != TRIM(name)
    """
  end

  def down do
    # Data migration - cannot be reversed as we don't know the original values
    :ok
  end
end
