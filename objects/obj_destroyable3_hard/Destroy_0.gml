if !in_saveroom()
	create_debris(random_range(bbox_left, bbox_right), random_range(bbox_top, bbox_bottom), spr_bigdebris_hard)

event_inherited()
