import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, BigInt } from "@graphprotocol/graph-ts"
import { AutomationSet } from "../generated/schema"
import { AutomationSet as AutomationSetEvent } from "../generated/RaffleMarketplace/RaffleMarketplace"
import { handleAutomationSet } from "../src/raffle-marketplace"
import { createAutomationSetEvent } from "./raffle-marketplace-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#tests-structure

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let automation = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let newAutomationSetEvent = createAutomationSetEvent(automation)
    handleAutomationSet(newAutomationSetEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#write-a-unit-test

  test("AutomationSet created and stored", () => {
    assert.entityCount("AutomationSet", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "AutomationSet",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "automation",
      "0x0000000000000000000000000000000000000001"
    )

    // More assert options:
    // https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#asserts
  })
})
