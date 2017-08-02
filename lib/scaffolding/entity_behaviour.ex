#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.Scaffolding.EntityBehaviour do
  @moduledoc("""
  This Behaviour provides some callbacks needed for the Noizu.ERP (EntityReferenceProtocol) to work smoothly.
  """)

  #-----------------------------------------------------------------------------
  # aliases, imports, uses,
  #-----------------------------------------------------------------------------
  require Logger

  #-----------------------------------------------------------------------------
  # Behaviour definition and types.
  #-----------------------------------------------------------------------------
  @type nmid :: integer | atom | String.t | tuple
  @type entity_obj :: any
  @type entity_record :: any
  @type entity_tuple_reference :: {:ref, module, nmid}
  @type entity_string_reference :: String.t
  @type entity_reference :: entity_obj | entity_record | entity_tuple_reference | entity_string_reference
  @type details :: any
  @type error :: {:error, details}
  @type options :: Map.t | nil

  @doc """
    Returns appropriate {:ref|:ext_ref, module, identifier} reference tuple
  """
  @callback ref(entity_reference) :: entity_tuple_reference | error

  @doc """
    Returns appropriate string encoded ref. E.g. ref.user.1234
  """
  @callback sref(entity_reference) :: entity_string_reference | error

  @doc """
    Returns entity, given an identifier, ref tuple, ref string or other known identifier type.
    Where an entity is a EntityBehaviour implementing struct.
  """
  @callback entity(entity_reference, options) :: entity_obj | error

  @doc """
    Returns entity, given an identifier, ref tuple, ref string or other known identifier type. Wrapping call in transaction if required.
    Where an entity is a EntityBehaviour implementing struct.
  """
  @callback entity!(entity_reference, options) :: entity_obj | error

  @doc """
    Returns record, given an identifier, ref tuple, ref string or other known identifier type.
    Where a record is the raw mnesia table entry, as opposed to a EntityBehaviour based struct object.
  """
  @callback record(entity_reference, options) :: entity_record | error

  @doc """
    Returns record, given an identifier, ref tuple, ref string or other known identifier type. Wrapping call in transaction if required.
    Where a record is the raw mnesia table entry, as opposed to a EntityBehaviour based struct object.
  """
  @callback record!(entity_reference, options) :: entity_record | error

  @doc """
    Converts entity into record format. Aka extracts any fields used for indexing with the expected database table looking something like
    ```
      %Table{
        identifier: entity.identifier,
        ...
        any_indexable_fields: entity.indexable_field,
        ...
        entity: entity
      }
    ```
    The default implementation assumes table structure if simply `%Table{identifier: entity.identifier, entity: entity}` therefore you will need to
    overide this implementation if you have any indexable fields. Future versions of the entity behaviour will accept an indexable field option
    that will insert expected fields and (if indicated) do simple type casting such as transforming DateTime.t fields into utc time stamps or
    `{time_zone, year, month, day, hour, minute, second}` tuples for efficient range querying.
  """
  @callback as_record(entity_obj) :: entity_record | error

  @doc """
    Returns the string used for preparing sref format strings. E.g. a `User` struct might use the string ``"user"`` as it's sref_module resulting in
    sref strings like `ref.user.1234`.
  """
  @callback sref_module() :: String.t

  #-----------------------------------------------------------------------------
  # Defines
  #-----------------------------------------------------------------------------
  @methods([:ref, :sref, :entity, :entity!, :record, :record!, :erp_imp, :as_record, :sref_module])

  #-----------------------------------------------------------------------------
  # Default Implementations
  #-----------------------------------------------------------------------------
  defmodule DefaultImplementation do
    @callback ref_implementation(table :: Module, sref_prefix :: String.t) :: Macro.t
    @callback sref_implementation(table :: Module, sref_prefix :: String.t) :: Macro.t
    @callback entity_implementation(table :: Module, repo :: Module) :: Macro.t
    @callback entity_txn_implementation(table :: Module, repo :: Module) :: Macro.t
    @callback record_implementation(table :: Module, repo :: Module) :: Macro.t
    @callback record_txn_implementation(table :: Module, repo :: Module) :: Macro.t

    @doc """
      Noizu.ERP Implementation
    """
    @callback erp_imp(table :: Module) :: Macro.t

    def ref_implementation(table, sref_prefix) do
      quote do
        def ref(identifier) when is_integer(identifier) do
          {:ref, __MODULE__, identifier}
        end
        def ref("ref." <> unquote(sref_prefix) <> identifier = sref) do
          Noizu.ERP.ref(identifier)
        end
        def ref(identifier) when is_bitstring(identifier) do
          {:ref, __MODULE__, String.to_integer(identifier)}
        end
        def ref(identifier) when is_atom(identifier) do
          {:ref, __MODULE__, identifier}
        end
        def ref(%{__struct__: __MODULE__} = entity) do
          {:ref, __MODULE__, entity.identifier}
        end
        def ref(%unquote(table){} = record) do
          {:ref, __MODULE__, record.identifier}
        end
        def ref(any) do
          raise "#{__MODULE__}.ref Unsupported item #{inspect any}"
        end
      end # end quote
    end # end defmacro ref

    def sref_implementation(table, sref_prefix) do
      quote do
        def sref(identifier) when is_integer(identifier) do
          unquote(sref_prefix) <> identifier
        end
        def sref("ref." <> unquote(sref_prefix) <> identifier = sref) do
          sref
        end
        def sref(identifier) when is_bitstring(identifier) do
          unquote(sref_prefix) <> identifier
        end
        def sref(identifier) when is_atom(identifier) do
          unquote(sref_prefix) <> Atom.to_string(identifier)
        end
        def sref(%{__struct__: __MODULE__} = entity) do
          unquote(sref_prefix) <> entity.identifier
        end
        def sref(%unquote(table){} = record) do
          unquote(sref_prefix) <> record.identifier
        end
        def sref(any) do
          raise "#{__MODULE__}.sref Unsupported item #{inspect any}"
        end
      end # end quote
    end # end defmacro ref

    def entity_implementation(table, repo) do
      quote do
        def entity(item, options \\ nil)
        def entity(%{__struct__: __MODULE__} = entity, options) when options == %{} or options == nil do
          entity
        end
        def entity(%unquote(table){} = record, options) when options == %{} or options == nil do
          record.entity
        end
        def entity(identifier, options) do
          unquote(repo).get(__MODULE__.ref(identifier), Noizu.Scaffolding.CallingContext.internal(), options)
        end
        def entity(any, _options) do
          raise "#{__MODULE__}.entity Unsupported item #{inspect any}"
        end
      end # end quote
    end # end defmacro ref

    def entity_txn_implementation(table, repo) do
      quote do
        def entity!(item, options \\ nil)
        def entity!(%{__struct__: __MODULE__} = entity, options) when options == %{} or options == nil do
          entity
        end
        def entity!(%unquote(table){} = record, options) when options == %{} or options == nil do
          record.entity
        end
        def entity!(identifier, options) do
          unquote(repo).get!(__MODULE__.ref(identifier), Noizu.Scaffolding.CallingContext.internal(), options)
        end
        def entity!(any, _options) do
          raise "#{__MODULE__}.entity! Unsupported item #{inspect any}"
        end
      end # end quote
    end # end defmacro ref

    def record_implementation(table, repo) do
      quote do
        def record(item, options \\ nil)
        def record(%{__struct__: __MODULE__} = entity, options) when options == %{} or options == nil do
          __MODULE__.as_record(entity)
        end
        def record(%unquote(table){} = record, options) when options == %{} or options == nil do
          record
        end
        def record(identifier, options) do
          entity = unquote(repo).get(__MODULE__.ref(identifier), Noizu.Scaffolding.CallingContext.internal(), options)
          __MODULE__.as_record(entity)
        end
        def record(any, _options) do
          raise "#{__MODULE__}.record Unsupported item #{inspect any}"
        end
      end # end quote
    end # end defmacro ref

    def record_txn_implementation(table, repo) do
      quote do
        def record!(item, options \\ nil)
        def record!(%{__struct__: __MODULE__} = entity, options) when options == %{} or options == nil do
          __MODULE__.as_record(entity)
        end
        def record!(%unquote(table){} = record, options) when options == %{} or options == nil do
          record
        end
        def record!(identifier, options) do
          unquote(repo).get!(__MODULE__.ref(identifier), Noizu.Scaffolding.CallingContext.internal(), options)
          |> __MODULE__.as_record()
        end
        def record!(any, _options) do
          raise "#{__MODULE__}.record! Unsupported item #{inspect any}"
        end
      end # end quote
    end # end defmacro ref

    def erp_imp(table) do
      quote do
        parent_module = __MODULE__
        defimpl Noizu.ERP, for: [__MODULE__, unquote(table)] do
          @parent_module(parent_module)
          def ref(o), do: @parent_module.ref(o)
          def sref(o), do: @parent_module.sref(o)
          def entity(o, options), do: @parent_module.entity(o, options)
          def entity!(o, options), do: @parent_module.entity!(o, options)
          def record(o, options) do
             @parent_module.record(o, options)
          end
          def record!(o, options), do: @parent_module.record!(o, options)
        end
      end # end quote
    end # end defmacro
  end # end defmodule

  #-----------------------------------------------------------------------------
  # Using Implementation
  #-----------------------------------------------------------------------------
  defmacro __using__(options) do
    # Only include implementation for these methods.
    option_arg = Keyword.get(options, :only, @methods)
    only = List.foldl(@methods, %{}, fn(method, acc) -> Map.put(acc, method, Enum.member?(option_arg, method)) end)

    # Don't include implementation for these methods.
    option_arg = Keyword.get(options, :override, [])
    override = List.foldl(@methods, %{}, fn(method, acc) -> Map.put(acc, method, Enum.member?(option_arg, method)) end)

    # Repo module (entity/record implementation), Module name with "Repo" appeneded if :auto
    repo_module = Keyword.get(options, :repo_module, :auto)
    mnesia_table = Keyword.get(options, :mnesia_table)

    # Default Implementation Provider
    default_implementation = Keyword.get(options, :default_implementation, DefaultImplementation)

    sm = Keyword.get(options, :sref_module, "unsupported")
    sref_prefix = "ref." <> sm <> "."

    quote do
      import unquote(__MODULE__)
      @behaviour Noizu.Scaffolding.EntityBehaviour

      # Repo
      if (unquote(repo_module) == :auto) do
        rm = Module.split(__MODULE__) |> Enum.slice(0..-2) |> Module.concat
        m = (Module.split(__MODULE__) |> List.last()) <> "Repo"
        @repo_module Module.concat([rm, m])
      else
        @repo_module(unquote(repo_module))
      end

      if (unquote(only.as_record) && !unquote(override.as_record)) do
        def as_record(this) do
          %unquote(mnesia_table) {
            identifier: this.identifier,
            entity: this
          }
        end
      end

      if (unquote(only.sref_module) && !unquote(override.sref_module)) do
        def sref_module() do
          unquote(sm)
        end
      end

      #-------------------------------------------------------------------------
      # Default Implementation from default_implementation behaviour
      #-------------------------------------------------------------------------
      if (unquote(only.ref) && !unquote(override.ref)) do
        unquote(default_implementation.ref_implementation(mnesia_table, sref_prefix))
      end
      if (unquote(only.sref) && !unquote(override.sref)) do
        unquote(default_implementation.sref_implementation(mnesia_table, sref_prefix))
      end
      if (unquote(only.entity) && !unquote(override.entity)) do
        unquote(default_implementation.entity_implementation(mnesia_table, repo_module))
      end
      if (unquote(only.entity!) && !unquote(override.entity!)) do
        unquote(default_implementation.entity_txn_implementation(mnesia_table, repo_module))
      end
      if (unquote(only.record) && !unquote(override.record)) do
        unquote(default_implementation.record_implementation(mnesia_table, repo_module))
      end
      if (unquote(only.record!) && !unquote(override.record!)) do
        unquote(default_implementation.record_txn_implementation(mnesia_table, repo_module))
      end
      if (unquote(only.erp_imp) && !unquote(override.erp_imp)) do
        unquote(default_implementation.erp_imp(mnesia_table))
      end
    end # end quote
  end # end defmacro
end #end defmodule