--!strict
-- Weapon systems. Shared: the server runs combat with these, the client shows
-- them in the hangar. One weapon per faction specialisation.
-- Icons stick to glyphs Roblox's UI font actually ships - fancier arrows render
-- as empty boxes.

return {
	Bullets = {
		Name = "Autocannons",
		Icon = "\u{25CF}\u{25CF}\u{25CF}",
		Blurb = "Fast shells. High sustained damage up close, but a moving target can dodge them.",
		Range = 250,
		Damage = 8,
		Cooldown = 1.2,
		Speed = 300,
	},
	Rockets = {
		Name = "Rocket Pods",
		Icon = "\u{00BB}\u{00BB}",
		Blurb = "Ejected wide, then they turn and burn. Cannot miss - but a fast ship outruns their fuel.",
		Range = 300,
		Damage = 25,
		Cooldown = 4.0,
		TopSpeed = 130,
		Fuel = 700,
	},
	Laser = {
		Name = "Beam Battery",
		Icon = "\u{2014}\u{2014}",
		Blurb = "Long-range beams that flicker and fade. Slow cycle, heavy alpha strike.",
		Range = 500,
		Damage = 40,
		Cooldown = 6.0,
		Duration = 0.45,
	},
}