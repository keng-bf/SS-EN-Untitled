depth = 3
logoArray = [spr_FMOD_logo, spr_biggnomestudios_logo]
logoIndex = 0
logoChangeBufferMax = 100
logoChangeBuffer = logoChangeBufferMax
completed = false
playedGnome = false
if global.skipintro
	room_goto_fixed(rm_mainmenu)