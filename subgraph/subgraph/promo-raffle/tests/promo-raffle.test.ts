import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, Bytes, BigInt } from "@graphprotocol/graph-ts"
import { RaffleEnter } from "../generated/schema"
import { RaffleEnter as RaffleEnterEvent } from "../generated/PromoRaffle/PromoRaffle"
import { handleRaffleEnter } from "../src/promo-raffle"
import { createRaffleEnterEvent } from "./promo-raffle-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#tests-structure

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let _player = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let _ip = "Example string value"
    let _country3 = Bytes.fromI32(1234567890)
    let _lastTimestamp = BigInt.fromI32(234)
    let newRaffleEnterEvent = createRaffleEnterEvent(
      _player,
      _ip,
      _country3,
      _lastTimestamp
    )
    handleRaffleEnter(newRaffleEnterEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#write-a-unit-test

  test("RaffleEnter created and stored", () => {
    assert.entityCount("RaffleEnter", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "RaffleEnter",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "_player",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "RaffleEnter",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "_ip",
      "Example string value"
    )
    assert.fieldEquals(
      "RaffleEnter",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "_country3",
      "1234567890"
    )
    assert.fieldEquals(
      "RaffleEnter",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "_lastTimestamp",
      "234"
    )

    // More assert options:
    // https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#asserts
  })
})
