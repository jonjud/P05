extends Resource
class_name ItemData

enum ItemType { MATERIAL, TOOL, WEAPON, ARMOR, ACCESSORY, CONSUMABLE, BUILDING, FURNITURE, QUEST, MISC }
enum MaterialForm { NONE, RAW, REFINED, COMPONENT, FINISHED, BYPRODUCT, UNIQUE }
enum Rarity { COMMON } # ค่าอื่นยัง OPEN (OQ-04-03)

@export var id: StringName # stable unique key
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var max_stack: int = 99
@export var item_type: ItemType = ItemType.MISC
@export var material_form: MaterialForm = MaterialForm.NONE
@export var tags: Array[StringName] = []# tier1, wood, salvageable, furniture ฯลฯ
@export var rarity: Rarity = Rarity.COMMON
@export var value: int = 0                   # base economic value
@export var can_be_salvaged: bool = true
@export var salvage_yield: Array[SalvageEntry] = []
@export var salvage_station: StringName = &"any"
