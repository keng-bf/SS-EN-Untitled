if !in_saveroom()
{
	create_small_number((x - sprite_xoffset) + (sprite_width / 2), (y - sprite_yoffset) + (sprite_height / 2), "50")
	global.Collect += 50
	global.PizzaMeter += 1
	global.ComboTime += 20
}
