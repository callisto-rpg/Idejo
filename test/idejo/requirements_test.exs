# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.RequirementsTest do
  use ExUnit.Case, async: true

  alias Idejo.Requirements

  # MVP requirements whose tests come with a later pull request of M5 (MVP §7). Remove an ID
  # when its tests land: the last test below fails until then.
  @pending %{
    "AD-05" => "nightly backup and restore, pull request #74",
    "AX-01" => "accessibility audit (keyboard, focus, landmarks), next in M5",
    "NF-01" => "load test, live delivery within 200 ms",
    "NF-03" => "page speed on a mid-range phone, measured with the load test",
    "NF-04" => "load test on 2 vCPU / 2 GB",
    "LI-05" => "the CLA document (docs/legal/CLA.md) is not in the repository yet"
  }

  # MVP requirements on how people work, which no test can check: a person verifies them in
  # review (pull request template).
  @by_review %{
    "DV-05" => "one requirement per pull request, reviewed by a person",
    "LI-08" => "the steward writes the specifications and reviews every change"
  }

  @tag req: "DV-02"
  test "DV-02 every MVP requirement has tests named after it" do
    tested = MapSet.new(Requirements.tagged_tests(), &elem(&1, 0))

    missing =
      for id <- Requirements.mvp(),
          id not in tested,
          not Map.has_key?(@pending, id),
          not Map.has_key?(@by_review, id),
          do: id

    assert missing == [], "MVP requirements without a test tagged req: ID: #{inspect(missing)}"
  end

  @tag req: "DV-02"
  test "DV-02 each tagged test is named after its ID, and every ID exists" do
    known = MapSet.new(Requirements.v1() ++ Requirements.mvp())

    for {id, name, place} <- Requirements.tagged_tests() do
      assert id in known, "#{place}: #{id} is in neither specification"
      assert name, "#{place}: no test after @tag req: #{inspect(id)}"

      assert String.starts_with?(name, id <> " "),
             "#{place}: #{inspect(name)} must start with #{id}"
    end
  end

  @tag req: "DV-02"
  test "DV-02 the lists of exceptions stay true" do
    mvp = Requirements.mvp()
    tested = MapSet.new(Requirements.tagged_tests(), &elem(&1, 0))

    for id <- Map.keys(@pending) ++ Map.keys(@by_review) do
      assert id in mvp, "#{id} is not an MVP requirement"
    end

    for {id, why} <- @pending do
      refute id in tested, "#{id} has tests now (was pending: #{why}); remove it from @pending"
    end
  end
end
