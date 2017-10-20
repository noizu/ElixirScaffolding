#-------------------------------------------------------------------------------
# Author: Keith Brings
# Copyright (C) 2017 Noizu Labs, Inc. All rights reserved.
#-------------------------------------------------------------------------------

defmodule Noizu.Scaffolding.QueryStrategy.Default do
  @behaviour Noizu.Scaffolding.QueryBehaviour
  alias Noizu.Scaffolding.CallingContext
  alias Amnesia.Table, as: T
  #alias Amnesia.Table.Selection, as: S
  require Exquisite


  def match(_match_sel, _mnesia_table, %CallingContext{} = _context, _options) do
    raise "Match NYI"
  end

  def list(mnesia_table, %CallingContext{} = _context, options) do
    pg = options[:pg] || 1
    rpp = options[:rpp] || 5000
    qspec = if options[:filter] do
      {options[:filter][:comparison] || :==, options[:filter][:field], options[:filter][:value]}
    else
      {:==, true, true}
    end

    a = for index <- 1..Enum.count(mnesia_table.attributes()) do
      String.to_atom("$#{index}")
    end
    t = List.to_tuple([mnesia_table] ++ a)
    spec = [{t, [qspec], [:"$_"]}]
    raw = T.select(mnesia_table, rpp, spec)
    case raw do
      nil -> nil
      :badarg -> :badarg
      raw ->
        raw = if pg > 1, do: Enum.reduce(2..pg, raw, fn(_i, a) -> Amnesia.Selection.next(a) end), else: raw
        if raw == nil, do: nil, else: %Amnesia.Table.Select{raw| coerce: mnesia_table}
    end
  end

  def get(identifier, mnesia_table,  %CallingContext{} = _context, options) do
    if options[:dirty] do
      mnesia_table.read!(identifier)
    else
      mnesia_table.read(identifier)
    end
  end

  def update(entity, mnesia_table,  %CallingContext{} = _context, options) do
    if options[:dirty] do
      mnesia_table.write!(entity)
    else
      mnesia_table.write(entity)
    end
  end

  def create(entity, mnesia_table,  %CallingContext{} = _context, options) do
    if options[:dirty] do
      mnesia_table.write!(entity)
    else
      mnesia_table.write(entity)
    end
  end

  def delete(identifier, mnesia_table,  %CallingContext{} = _context, options) do
    if options[:dirty] do
      mnesia_table.delete!(identifier)
    else
      mnesia_table.delete(identifier)
    end
  end

end
