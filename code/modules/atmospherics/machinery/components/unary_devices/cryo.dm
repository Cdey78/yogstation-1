#define CRYOMOBS 'icons/obj/cryo_mobs.dmi'

/obj/machinery/atmospherics/components/unary/cryo_cell
	name = "cryo cell"
	icon = 'icons/obj/cryogenics.dmi'
	icon_state = "pod-off"
	density = 1
	anchored = 1


	var/on = FALSE
	state_open = FALSE
	var/autoeject = FALSE
	var/volume = 100

	var/running_bob_anim = FALSE
	var/timer_id

	var/efficiency = 1
	var/sleep_factor = 750
	var/paralyze_factor = 1000
	var/heat_capacity = 20000
	var/conduction_coefficient = 0.30

	var/obj/item/weapon/reagent_containers/glass/beaker = null
	var/reagent_transfer = 0

/obj/machinery/atmospherics/components/unary/cryo_cell/New()
	..()
	initialize_directions = dir
	var/obj/item/weapon/circuitboard/machine/B = new /obj/item/weapon/circuitboard/machine/cryo_tube(null)
	B.apply_default_parts(src)

/obj/item/weapon/circuitboard/machine/cryo_tube
	name = "circuit board (Cryotube)"
	build_path = /obj/machinery/atmospherics/components/unary/cryo_cell
	origin_tech = "programming=4;biotech=3;engineering=4;plasmatech=3"
	req_components = list(
							/obj/item/weapon/stock_parts/matter_bin = 1,
							/obj/item/stack/cable_coil = 1,
							/obj/item/weapon/stock_parts/console_screen = 1,
							/obj/item/stack/sheet/glass = 2)

/obj/machinery/atmospherics/components/unary/cryo_cell/construction()
	..(dir, dir)

/obj/machinery/atmospherics/components/unary/cryo_cell/RefreshParts()
	var/C
	for(var/obj/item/weapon/stock_parts/matter_bin/M in component_parts)
		C += M.rating

	efficiency = initial(efficiency) * C
	sleep_factor = initial(sleep_factor) * C
	paralyze_factor = initial(paralyze_factor) * C
	heat_capacity = initial(heat_capacity) / C
	conduction_coefficient = initial(conduction_coefficient) * C

/obj/machinery/atmospherics/components/unary/cryo_cell/Destroy()
	beaker = null
	return ..()

/obj/machinery/atmospherics/components/unary/cryo_cell/update_icon()
	cut_overlays()

	if(state_open)
		icon_state = "pod-open"
	else if(occupant)
		var/image/occupant_overlay

		if(ismonkey(occupant)) // Monkey
			occupant_overlay = image(CRYOMOBS, "monkey")

		else if(isalienadult(occupant))

			if(isalienroyal(occupant)) // Queen and prae
				occupant_overlay = image(CRYOMOBS, "alienq")

			else if(isalienhunter(occupant)) // Hunter
				occupant_overlay = image(CRYOMOBS, "alienh")

			else if(isaliensentinel(occupant)) // Sentinel
				occupant_overlay = image(CRYOMOBS, "aliens")

			else // Drone (or any other alien that isn't any of the above)
				occupant_overlay = image(CRYOMOBS, "aliend")

		else if(ishuman(occupant) || islarva(occupant) || (isanimal(occupant) && !ismegafauna(occupant))) // Mobs that are smaller than cryotube
			occupant_overlay = image(occupant.icon, occupant.icon_state)
			occupant_overlay.overlays = occupant.overlays.Copy()
		else // Anything else
			occupant_overlay = image(CRYOMOBS, "generic")

		occupant_overlay.dir = SOUTH
		occupant_overlay.pixel_y = 22

		if(on && !running_bob_anim && is_operational())
			icon_state = "pod-on"
			running_bob_anim = TRUE
			run_bob_anim(TRUE, occupant_overlay)
		else
			icon_state = "pod-off"
			add_overlay(occupant_overlay)
			add_overlay("cover-off")
	else if(on && is_operational())
		icon_state = "pod-on"
		add_overlay("cover-on")
	else
		icon_state = "pod-off"
		add_overlay("cover-off")

	if(panel_open)
		add_overlay("pod-panel")

/obj/machinery/atmospherics/components/unary/cryo_cell/process()
	..()
	if(!on)
		return
	if(!is_operational())
		on = FALSE
		update_icon()
		return
	var/datum/gas_mixture/air1 = AIR1
	if(occupant)
		var/mob/living/carbon/human/H = occupant
		if(occupant.health >= 100 || (istype(H) && H.dna && H.dna.species && (DAMAGE_CHEMICAL in H.dna.species.heal_immunities)) ) // Don't bother with fully healed people or people that cryo cannot heal.
			on = FALSE
			update_icon()
			playsound(src.loc, 'sound/machines/ding.ogg', volume, 1) // Bug the doctors.
			if(autoeject) // Eject if configured.
				open_machine()
			return
		else if(occupant.stat == DEAD) // We don't bother with dead people.
			return

		if(occupant.bodytemperature < T0C) // Sleepytime. Why? More cryo magic.
			occupant.Sleeping((occupant.bodytemperature / sleep_factor) * 100)
			occupant.Paralyse((occupant.bodytemperature / paralyze_factor) * 100)

		if(beaker)
			if(reagent_transfer == 0) // Magically transfer reagents. Because cryo magic.
				beaker.reagents.trans_to(occupant, 1, 10 * efficiency) // Transfer reagents, multiplied because cryo magic.
				beaker.reagents.reaction(occupant, VAPOR)
				air1.gases["o2"][MOLES] -= 2 / efficiency // Lets use gas for this.
			if(++reagent_transfer >= 10 * efficiency) // Throttle reagent transfer (higher efficiency will transfer the same amount but consume less from the beaker).
				reagent_transfer = 0
	return 1

/obj/machinery/atmospherics/components/unary/cryo_cell/process_atmos()
	..()
	if(!on)
		return
	var/datum/gas_mixture/air1 = AIR1
	if(!NODE1 || !AIR1 || air1.gases["o2"][MOLES] < 5) // Turn off if the machine won't work.
		on = FALSE
		update_icon()
		return
	if(occupant)
		var/cold_protection = 0
		var/mob/living/carbon/human/H = occupant
		if(istype(H))
			cold_protection = H.get_cold_protection(air1.temperature)

		var/temperature_delta = air1.temperature - occupant.bodytemperature // The only semi-realistic thing here: share temperature between the cell and the occupant.
		if(abs(temperature_delta) > 1)
			var/air_heat_capacity = air1.heat_capacity()
			var/heat = ((1 - cold_protection) / 10 + conduction_coefficient) \
						* temperature_delta * \
						(air_heat_capacity * heat_capacity / (air_heat_capacity + heat_capacity))
			air1.temperature = max(air1.temperature - heat / air_heat_capacity, TCMB)
			occupant.bodytemperature = max(occupant.bodytemperature + heat / heat_capacity, TCMB)

		air1.gases["o2"][MOLES] -= 0.5 / efficiency // Magically consume gas? Why not, we run on cryo magic.

/obj/machinery/atmospherics/components/unary/cryo_cell/power_change()
	..()
	update_icon()

/obj/machinery/atmospherics/components/unary/cryo_cell/relaymove(mob/living/user)
	if(user.last_special <= world.time)
		container_resist(user)

/obj/machinery/atmospherics/components/unary/cryo_cell/open_machine()
	if(!state_open && !panel_open)
		on = FALSE
		running_bob_anim = FALSE
		// TODO: Update Yog's timer system and remove this filty hack
		if(timer_id)
			deltimer(timer_id)
			timer_id = null
		playsound(loc, 'sound/machines/windowdoor.ogg', 50, 1)
		..()
		if(beaker)
			beaker.loc = src

/obj/machinery/atmospherics/components/unary/cryo_cell/close_machine(mob/living/carbon/user)
	if((isnull(user) || istype(user)) && state_open && !panel_open)
		playsound(loc, 'sound/machines/windowdoor.ogg', 50, 1)
		..(user)
		return occupant

/obj/machinery/atmospherics/components/unary/cryo_cell/container_resist(mob/living/user)
	user.last_special = world.time + CLICK_CD_BREAKOUT
	to_chat(user, "<span class='notice'>You struggle inside the cryotube, kicking the release with your foot... (This will take around 30 seconds.)</span>")
	audible_message("<span class='notice'>You hear a thump from [src].</span>")
	if(do_after(user, 300))
		if(occupant == user) // Check they're still here.
			open_machine()

/obj/machinery/atmospherics/components/unary/cryo_cell/examine(mob/user)
	..()
	if(occupant)
		if(on)
			to_chat(user, "Someone's inside [src]!")
		else
			to_chat(user, "You can barely make out a form floating in [src].")
	else
		to_chat(user, "[src] seems empty.")

/obj/machinery/atmospherics/components/unary/cryo_cell/MouseDrop_T(mob/target, mob/user)
	if(user.stat || user.lying || !Adjacent(user) || !user.Adjacent(target) || !iscarbon(target) || !user.IsAdvancedToolUser())
		return
	close_machine(target)

/obj/machinery/atmospherics/components/unary/cryo_cell/attackby(obj/item/I, mob/user, params)
	if(istype(I, /obj/item/weapon/reagent_containers/glass))
		. = 1 //no afterattack
		if(!user.drop_item())
			return
		if(beaker)
			to_chat(user, "<span class='warning'>A beaker is already loaded into [src]!</span>")
			return
		beaker = I
		I.loc = src
		user.visible_message("[user] places [I] in [src].", \
							"<span class='notice'>You place [I] in [src].</span>")
		return
	if(!on && !occupant && !state_open)
		if(default_deconstruction_screwdriver(user, "cell-o", "cell-off", I))
			return
		if(exchange_parts(user, I))
			return
	if(default_change_direction_wrench(user, I))
		return
	if(default_pry_open(I))
		return
	if(default_deconstruction_crowbar(I))
		return
	return ..()

/obj/machinery/atmospherics/components/unary/cryo_cell/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = 0, \
																	datum/tgui/master_ui = null, datum/ui_state/state = notcontained_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "cryo", name, 400, 550, master_ui, state)
		ui.open()

/obj/machinery/atmospherics/components/unary/cryo_cell/ui_data()
	var/list/data = list()
	data["isOperating"] = on
	data["hasOccupant"] = occupant ? 1 : 0
	data["isOpen"] = state_open
	data["autoEject"] = autoeject

	var/list/occupantData = list()
	if(occupant)
		occupantData["name"] = occupant.name
		occupantData["stat"] = occupant.stat
		occupantData["health"] = occupant.health
		occupantData["maxHealth"] = occupant.maxHealth
		occupantData["minHealth"] = config.health_threshold_dead
		occupantData["bruteLoss"] = occupant.getBruteLoss()
		occupantData["oxyLoss"] = occupant.getOxyLoss()
		occupantData["toxLoss"] = occupant.getToxLoss()
		occupantData["fireLoss"] = occupant.getFireLoss()
		occupantData["bodyTemperature"] = occupant.bodytemperature
	data["occupant"] = occupantData


	var/datum/gas_mixture/air1 = AIR1
	data["cellTemperature"] = round(air1.temperature)

	data["isBeakerLoaded"] = beaker ? 1 : 0
	var beakerContents = list()
	if(beaker && beaker.reagents && beaker.reagents.reagent_list.len)
		for(var/datum/reagent/R in beaker.reagents.reagent_list)
			beakerContents += list(list("name" = R.name, "volume" = R.volume))
	data["beakerContents"] = beakerContents
	return data

/obj/machinery/atmospherics/components/unary/cryo_cell/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("power")
			if(on)
				on = FALSE
				running_bob_anim = FALSE
				// TODO: Update Yog's timer system and remove this filty hack
				// This prevents multiple bobanimations being queued by turning it on/off quickly
				if(timer_id)
					deltimer(timer_id)
					timer_id = null
			else if(!state_open)
				on = TRUE
			. = TRUE
			update_icon()
		if("door")
			if(state_open)
				close_machine()
			else
				open_machine()
			. = TRUE
			update_icon()
		if("autoeject")
			autoeject = !autoeject
			. = TRUE
		if("ejectbeaker")
			if(beaker)
				beaker.forceMove(loc)
				if(get_dist(src, usr) <= 1 && !issilicon(usr))
					usr.put_in_hands(beaker)
				beaker = null
				. = TRUE

/obj/machinery/atmospherics/components/unary/cryo_cell/update_remote_sight(mob/living/user)
	return //we don't see the pipe network while inside cryo.

/obj/machinery/atmospherics/components/unary/cryo_cell/get_remote_view_fullscreens(mob/user)
	user.overlay_fullscreen("remote_view", /obj/screen/fullscreen/impaired, 1)

/obj/machinery/atmospherics/components/unary/cryo_cell/can_crawl_through()
	return //can't ventcrawl in or out of cryo.

/obj/machinery/atmospherics/components/unary/cryo_cell/can_see_pipes()
	return 0 //you can't see the pipe network when inside a cryo cell.

/obj/machinery/atmospherics/components/unary/cryo_cell/proc/run_bob_anim(anim_up, image/occupant_overlay)
	if(!on || !occupant || !is_operational())
		running_bob_anim = FALSE
		return
	cut_overlays()
	if(occupant_overlay.pixel_y != 23) // Same effect as occupant_overlay.pixel_y == 22 || occupant_overlay.pixel_y == 24
		anim_up = occupant_overlay.pixel_y == 22 // Same effect as if(occupant_overlay.pixel_y == 22) anim_up = TRUE ; if(occupant_overlay.pixel_y == 24) anim_up = FALSE
	if(anim_up)
		occupant_overlay.pixel_y++
	else
		occupant_overlay.pixel_y--
	add_overlay(occupant_overlay)
	add_overlay("cover-on")
	// TODO: Update our timer system and change this to TIMER_UNIQUE
	timer_id = addtimer(src, "run_bob_anim", 7, TIMER_NORMAL, anim_up, occupant_overlay) //hey yog your addtimer system sucks. sincerely, a /tg/coder.

#undef CRYOMOBS
