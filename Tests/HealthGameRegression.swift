import Foundation
// CSV is outside this engine test; no database or user files are opened.
enum HealthCSV { static func cell(_ s:String)->String { s } }
@main struct HealthGameRegression {
 static func main() throws {
  let now=Date();var s=HealthState();s.island.lastSettled=now;s.island.lastVisit=now;s.island.energy=10
  let sleeps=[Engine.SleepReward(id:"sleep-one",endedAt:now.addingTimeInterval(-60),durationSeconds:8*3600)]
  Engine.rewardSleep(&s,records:sleeps+sleeps,now:now)
  assert(s.island.energy == 34)
  Engine.rewardSleep(&s,records:sleeps,now:now);assert(s.island.energy == 34)
  Engine.rewardSleep(&s,records:[.init(id:"sleep-two",endedAt:now,durationSeconds:8*3600)],now:now);assert(s.island.energy == 34)
  assert(!Engine.placementAllowed(x:6.5,z:0,expansion:0))
  assert(Engine.placementAllowed(x:6.5,z:0,expansion:2))
  assert(!Engine.placementAllowed(x:Double.nan,z:0,expansion:3))
  s.island.buildings.insert("shelter");s.island.expansionLevel=2;s.island.placements["shelter"] = IslandPoint(x:6.5,z:0)
  try Engine.validate(s)
  let restored=try JSONDecoder().decode(HealthState.self,from:JSONEncoder().encode(s));try Engine.validate(restored)
  assert(restored.island.rewardedSleepIDs == s.island.rewardedSleepIDs)
  s.island.paused=true
  Engine.rewardSleep(&s,records:[.init(id:"paused",endedAt:now,durationSeconds:3600)],now:now)
  assert(!s.island.rewardedSleepIDs.contains("paused"))
  var game=HealthState();game.island.lastSettled=now;game.island.lastVisit=now;game.island.expansionLevel=3
  game.island.inventory=Dictionary(uniqueKeysWithValues:Catalog.materials.map { ($0,10000) })
  for r in Catalog.recipes.filter(\.tool) { try Engine.build(&game,id:r.id,now:now) }
  for r in Catalog.recipes.filter({ !$0.tool }) { try Engine.build(&game,id:r.id,now:now) }
  assert(game.island.buildings.count==14)
  try Engine.applyLayout(&game,placements:game.island.placements)
  let original=game.island.placements
  var collision=original;collision["orchard"]=collision["kitchen"]
  do { try Engine.applyLayout(&game,placements:collision);assertionFailure("Accepted overlap") } catch {}
  assert(game.island.placements==original)
  let fiber=Catalog.actions.first { $0.id=="fiber" }!
  assert(Engine.yield(game,fiber)==4 && Engine.energyCost(game,fiber)==4.75)
  game.island.energy=10;game.island.water=20;game.island.food=20
  game.ledgers[Engine.day(now,game)]=DailyLedger(welcomed:true)
  let rations=game.island.inventory["ration"]!
  Engine.visit(&game,now:now,welcome:false)
  assert(game.island.water==26 && game.island.inventory["ration"]==rations+9)
  let harvest=game.island.inventory;Engine.visit(&game,now:now,welcome:false);assert(harvest==game.island.inventory)
  let energy=game.island.energy,herbs=game.island.inventory["herb"]!
  try Engine.brewTea(&game,now:now);try Engine.brewTea(&game,now:now)
  assert(game.island.energy==energy+24 && game.island.inventory["herb"]==herbs-4)
  do { try Engine.brewTea(&game,now:now);assertionFailure("Exceeded daily tea cap") } catch {}
  try Engine.supply(&game,now:now);assert(game.island.food==28)
  try Engine.upgrade(&game,id:"workshop",now:now);assert(Engine.energyCost(game,fiber)==4.5)
  let legacy=try JSONDecoder().decode(DailyLedger.self,from:Data("{}".utf8));assert(legacy.teaUses==0)
  let expanded=try JSONDecoder().decode(HealthState.self,from:JSONEncoder().encode(game));try Engine.validate(expanded)
  assert(expanded.ledgers[Engine.day(now,game)]!.teaUses==2)
  let prosperity=game.island.prosperity, inventory=game.island.inventory, energyBefore=game.island.energy
  for _ in 0..<500 { Engine.log(&game,"test","test",now) }
  assert(game.island.logs.count==300 && game.island.prosperity==prosperity && game.island.inventory==inventory && game.island.energy==energyBefore)
  print("PASS Health expansion: 14 buildings, free placement, rejected collision atomicity, harvest idempotency, rain/orchard/workshop/windmill/kitchen/tea effects, upgrade effects, legacy/save roundtrip")
  print("PASS Health: sleep idempotency, duplicate batch, daily cap, paused mode, expansion placement, save roundtrip")
 }
}
