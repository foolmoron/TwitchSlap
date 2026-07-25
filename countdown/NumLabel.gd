extends Label

@onready var rotate: RotateParent = $RotateParent
@onready var sin_rotate: SinRotateParent = $SinRotateParent
var rotate_time := 0.0
var rotate_time_max := 0.25
var rotate_strength := 16

enum Lang {
	Decimal,
	Roman,
	Devanagari,
	Kanji,
}

var font_sizes_by_lang: Array[int] = [280, 280, 370, 340]

@export var lang: Lang = Lang.Decimal:
	set(value):
		lang = value
		num_current = num_current

@export_range(0, 999) var num_current: int = 0:
	set(value):
		num_current = value
		label_settings.font_size = font_sizes_by_lang[lang]
		print("lang: %d size: %d" % [lang, label_settings.font_size])
		match lang:
			Lang.Decimal:
				text = to_text_decimal(value)
			Lang.Roman:
				text = to_text_roman(value)
			Lang.Devanagari:
				text = to_text_devanagari(value)
			Lang.Kanji:
				text = to_text_kanji(value)

func _ready() -> void:
	GameManager.update_count_until_local_player.connect(func(count: int):
		num_current = count
		rotate_time = rotate_time_max
	)
	GameManager.on_hit.connect(func():
		lang = (lang + randi_range(1, Lang.size() - 1)) % Lang.size() as Lang
	)
	num_current = num_current

# Decimal
var nums_decimal: Array[String] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

func to_text_decimal(value: int) -> String:
	var t := ""
	while value > 0:
		t = nums_decimal[value % 10] + t
		value /= 10
	return t

# Devanagari
var nums_devanagari: Array[String] = ["०", "१", "२", "३", "४", "५", "६", "७", "८", "९"]

func to_text_devanagari(value: int) -> String:
	var t := ""
	while value > 0:
		t = nums_devanagari[value % 10] + t
		value /= 10
	return t

# Roman
func to_text_roman(value: int) -> String:
	var t := ""
	var roman_values: Array[int] = [900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var roman_symbols: Array[String] = ["CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	for i in roman_values.size():
		while value >= roman_values[i]:
			t += roman_symbols[i]
			value -= roman_values[i]
	return t

# Kanji
var nums_kanji: Array[String] = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

func to_text_kanji(value: int) -> String:
	var t := ""
	var hundreds := value / 100
	var tens := value / 10 % 10
	var ones := value % 10
	if hundreds > 0:
		if hundreds > 1:
			t += nums_kanji[hundreds]
		t += "百"
	if tens > 0:
		if tens > 1:
			t += nums_kanji[tens]
		t += "十"
	if ones > 0:
		t += nums_kanji[ones]
	return "\n".join(t.split(""))

# etc
func _process(delta: float) -> void:
	rotate_time -= delta
	if rotate_time > 0.0:
		sin_rotate.process_mode = Node.PROCESS_MODE_DISABLED
		rotate.process_mode = Node.PROCESS_MODE_INHERIT
		rotate.speed_deg = rotate_strength * 360.0 * pow(rotate_time / rotate_time_max, 2.5)
		print(rotate.speed_deg)
	else:
		sin_rotate.process_mode = Node.PROCESS_MODE_INHERIT
		rotate.process_mode = Node.PROCESS_MODE_DISABLED
