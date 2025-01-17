defmodule GnoTest do
  use ExUnit.Case
  doctest Gno

  test "greets the world" do
    assert Gno.hello() == :world
  end
end
