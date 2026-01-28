import {
  AutomationSet as AutomationSetEvent,
  RaffleCreated as RaffleCreatedEvent,
  RaffleNftCloned as RaffleNftClonedEvent,
  RaffleNftImplementationSet as RaffleNftImplementationSetEvent,
  RaffleStageUpdated as RaffleStageUpdatedEvent,
  RaffleStateUpdated as RaffleStateUpdatedEvent,
  TicketsSoldUpdated as TicketsSoldUpdatedEvent,
  VerifierSet as VerifierSetEvent,
  WinnersUpdated as WinnersUpdatedEvent
} from "../generated/RaffleMarketplace/RaffleMarketplace"
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
} from "../generated/schema"
import { Bytes } from "@graphprotocol/graph-ts"

export function handleAutomationSet(event: AutomationSetEvent): void {
  let entity = new AutomationSet(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.automation = event.params.automation

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRaffleCreated(event: RaffleCreatedEvent): void {
  let entity = new RaffleCreated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.raffleId = event.params.raffleId
  entity.raffleAddress = event.params.raffleAddress
  entity.hoster = event.params.raffleOwner
  entity.isVerifiedByMarketplace =
    event.params.raffle.isVerifiedByMarketplace
  entity.category = event.params.raffle.category
  entity.title = event.params.raffle.title
  entity.description = event.params.raffle.description
  entity.raffleDuration = event.params.raffle.raffleDuration
  entity.threshold = event.params.raffle.threshold
  entity.images = event.params.raffle.images
  entity.winners = changetype<Bytes[]>(event.params.raffle.winners)
  entity.raffleState = event.params.raffle.raffleState
  entity.charityInfo_charityName =
    event.params.raffle.charityInfo.charityName
  entity.charityInfo_charityAddress =
    event.params.raffle.charityInfo.charityAddress
  entity.charityInfo_percentToDonate =
    event.params.raffle.charityInfo.percentToDonate
  entity.stages = changetype<Bytes[]>(event.params.stages)
  entity.prizes = changetype<Bytes[]>(event.params.prizes)
  entity.ongoingStage = event.params.ongoingStage

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRaffleNftCloned(event: RaffleNftClonedEvent): void {
  let entity = new RaffleNftCloned(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.raffleId = event.params.raffleId
  entity.raffleNFT = event.params.raffleNFT

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRaffleNftImplementationSet(
  event: RaffleNftImplementationSetEvent
): void {
  let entity = new RaffleNftImplementationSet(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.nftImplementation = event.params.nftImplementation

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRaffleStageUpdated(event: RaffleStageUpdatedEvent): void {
  let entity = new RaffleStageUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.raffleId = event.params.raffleId
  entity.stage = event.params.stage

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRaffleStateUpdated(event: RaffleStateUpdatedEvent): void {
  let entity = new RaffleStateUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.raffleId = event.params.raffleId
  entity.state = event.params.state

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleTicketsSoldUpdated(event: TicketsSoldUpdatedEvent): void {
  let entity = new TicketsSoldUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.raffleId = event.params.raffleId
  entity.stage = event.params.stage
  entity.amount = event.params.amount
  entity.buyer = event.params.buyer

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleVerifierSet(event: VerifierSetEvent): void {
  let entity = new VerifierSet(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.verifier = event.params.verifier

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleWinnersUpdated(event: WinnersUpdatedEvent): void {
  let entity = new WinnersUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.raffleId = event.params.raffleId
  entity.winnersCount = event.params.winnersCount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
