import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts"
import {
  AutomationSet,
  RaffleCreated,
  RaffleNftCloned,
  RaffleNftImplementationSet,
  RaffleStageUpdated,
  RaffleStateUpdated,
  TicketsSoldUpdated,
  VerifierSet,
  WinnersUpdated
} from "../generated/RaffleMarketplace/RaffleMarketplace"

export function createAutomationSetEvent(automation: Address): AutomationSet {
  let automationSetEvent = changetype<AutomationSet>(newMockEvent())

  automationSetEvent.parameters = new Array()

  automationSetEvent.parameters.push(
    new ethereum.EventParam(
      "automation",
      ethereum.Value.fromAddress(automation)
    )
  )

  return automationSetEvent
}

export function createRaffleCreatedEvent(
  raffleId: BigInt,
  raffleAddress: Address,
  raffleOwner: Address
): RaffleCreated {
  let raffleCreatedEvent = changetype<RaffleCreated>(newMockEvent())

  raffleCreatedEvent.parameters = new Array()

  raffleCreatedEvent.parameters.push(
    new ethereum.EventParam(
      "raffleId",
      ethereum.Value.fromUnsignedBigInt(raffleId)
    )
  )
  raffleCreatedEvent.parameters.push(
    new ethereum.EventParam(
      "raffleAddress",
      ethereum.Value.fromAddress(raffleAddress)
    )
  )
  raffleCreatedEvent.parameters.push(
    new ethereum.EventParam(
      "raffleOwner",
      ethereum.Value.fromAddress(raffleOwner)
    )
  )

  return raffleCreatedEvent
}

export function createRaffleNftClonedEvent(
  raffleId: BigInt,
  raffleNFT: Address
): RaffleNftCloned {
  let raffleNftClonedEvent = changetype<RaffleNftCloned>(newMockEvent())

  raffleNftClonedEvent.parameters = new Array()

  raffleNftClonedEvent.parameters.push(
    new ethereum.EventParam(
      "raffleId",
      ethereum.Value.fromUnsignedBigInt(raffleId)
    )
  )
  raffleNftClonedEvent.parameters.push(
    new ethereum.EventParam("raffleNFT", ethereum.Value.fromAddress(raffleNFT))
  )

  return raffleNftClonedEvent
}

export function createRaffleNftImplementationSetEvent(
  nftImplementation: Address
): RaffleNftImplementationSet {
  let raffleNftImplementationSetEvent =
    changetype<RaffleNftImplementationSet>(newMockEvent())

  raffleNftImplementationSetEvent.parameters = new Array()

  raffleNftImplementationSetEvent.parameters.push(
    new ethereum.EventParam(
      "nftImplementation",
      ethereum.Value.fromAddress(nftImplementation)
    )
  )

  return raffleNftImplementationSetEvent
}

export function createRaffleStageUpdatedEvent(
  raffleId: BigInt,
  stage: i32
): RaffleStageUpdated {
  let raffleStageUpdatedEvent = changetype<RaffleStageUpdated>(newMockEvent())

  raffleStageUpdatedEvent.parameters = new Array()

  raffleStageUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "raffleId",
      ethereum.Value.fromUnsignedBigInt(raffleId)
    )
  )
  raffleStageUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "stage",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(stage))
    )
  )

  return raffleStageUpdatedEvent
}

export function createRaffleStateUpdatedEvent(
  raffleId: BigInt,
  state: i32
): RaffleStateUpdated {
  let raffleStateUpdatedEvent = changetype<RaffleStateUpdated>(newMockEvent())

  raffleStateUpdatedEvent.parameters = new Array()

  raffleStateUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "raffleId",
      ethereum.Value.fromUnsignedBigInt(raffleId)
    )
  )
  raffleStateUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "state",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(state))
    )
  )

  return raffleStateUpdatedEvent
}

export function createTicketsSoldUpdatedEvent(
  raffleId: BigInt,
  stage: i32,
  amount: BigInt,
  buyer: Address
): TicketsSoldUpdated {
  let ticketsSoldUpdatedEvent = changetype<TicketsSoldUpdated>(newMockEvent())

  ticketsSoldUpdatedEvent.parameters = new Array()

  ticketsSoldUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "raffleId",
      ethereum.Value.fromUnsignedBigInt(raffleId)
    )
  )
  ticketsSoldUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "stage",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(stage))
    )
  )
  ticketsSoldUpdatedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )
  ticketsSoldUpdatedEvent.parameters.push(
    new ethereum.EventParam("buyer", ethereum.Value.fromAddress(buyer))
  )

  return ticketsSoldUpdatedEvent
}

export function createVerifierSetEvent(verifier: Address): VerifierSet {
  let verifierSetEvent = changetype<VerifierSet>(newMockEvent())

  verifierSetEvent.parameters = new Array()

  verifierSetEvent.parameters.push(
    new ethereum.EventParam("verifier", ethereum.Value.fromAddress(verifier))
  )

  return verifierSetEvent
}

export function createWinnersUpdatedEvent(
  raffleId: BigInt,
  winnersCount: BigInt
): WinnersUpdated {
  let winnersUpdatedEvent = changetype<WinnersUpdated>(newMockEvent())

  winnersUpdatedEvent.parameters = new Array()

  winnersUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "raffleId",
      ethereum.Value.fromUnsignedBigInt(raffleId)
    )
  )
  winnersUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "winnersCount",
      ethereum.Value.fromUnsignedBigInt(winnersCount)
    )
  )

  return winnersUpdatedEvent
}
