# Skill reference (decoded `src/client/assets/skill.csv`)

Generated from the shipped UTF-16 table; regenerate with
`python tools_dev/skill_reference_gen.py` after changing the CSV.

## Column map (the two header rows, translated)

| Cols | Meaning | Notes |
|---|---|---|
| 0–6 | SerialID · skill name · behavior · target side · MP cost · cast delay (s) · recovery (s) | behavior values: ENEMY, MYSELF, PARTY_SINGLE, PARTY_ALL, ALLY, TOGGLE, TOGGLE_RADIATION, RADIATION, PASSIVE, BREATH, BOLT, GBOLT, SPHBOLT, SPHERE, CIRCLE, CLAN, POINT; "recovery" (ベンチタイム) is the post-use cooldown |
| 7 | Range | 2500 seen on ranged skills — engine units, melee = 0 |
| 8 | Learnable by growth (1/0) | |
| 9 | Level requirement | |
| 10–37 | Class learn flags (28) | Warrior/Gladiator/Knight/Juggernaut/Dragoon/General/Paladin · Scout/Archer/Agent/Vigilance/Predator/Assassin/Disturbance · Acolyte/Priest/Ascetic/Cleric/Enchanter/Monk/Exorcist · Mage/Wizard/Darklore/Warlock/Conjurer/Jester/Calamity |
| 38–65 | Auto-attack class flags (CN-support) | same 28-class order; only the first 14 (melee+scout families) ever set |
| 66–69 | Potential-skill acquisition reference + required potential values | |
| 70–75 | Skill-line / proficiency requirement | col 75 holds the line name (e.g. `MELEE_DEFENSE`) |
| 76–90 | Weapon usability flags | BareHAND, 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP (daggers), 2H_TRUMP, BOW, CROSSBOW, WAND, STAFF — none set = any weapon |
| 91 | Shield required flag | set by Blocking and the shield skills |
| 92 | Cast marker (#キャスト) | values 1/2, client anim hint |
| 93–96 | Interruptible · usable-while-sheathed · alignment · chant type | raw codes (e.g. `MELEE_NONE`) |
| 97–113 | Buff effect IDs ×5 · user buff IDs ×5 · effect log ID · caster log ID · icon ID · display flag · BEFORE_CAST · shield-move motion · fx-swap · special log | plumbing, mostly empty |
| 114–115 | Unlocks skill IDs | resolved to names in the table |
| 116–117 | Description | |

## Skills (591 rows, file order)

| ID | Name | Behavior | Target | MP | Cast | Recovery | Range | Lv | Classes | Weapons | Shield | Unlocks | Description |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|:-:|---|---|
| 100000501 | Provoke | ENEMY | ENEMY | 10 | 0 | 15 | 2500 | 5 | Warrior, Gladiator, Knight, Juggernaut, Dragoon, General, Paladin | ALL |  | Brewer | Taunts the enemy in order to enrage them. |
| 100001001 | Obscene Gesture | ENEMY | ENEMY | 12 | 0 | 10 | 2500 | 20 | Knight, General, Paladin | ALL |  | Providence | Taunts the enemy in order to enrage them, and draws their attention for a short while. |
| 100002001 | Guardian | PARTY_SINGLE | ALLY | 16 | 4 | 10 | 2000 |  | ALL | any |  | Eternal Dirge | Allows you to take damage in place of another party member. |
| 100002002 | Bore Brunt | PARTY_SINGLE | ALL | 16 | 4 | 0.5 | 2500 | 50 | General | ALL |  | Eternal Dirge | Allows you to take damage in place of the targeted party member. This can be used on up to three people at once. |
| 100051001 | Lunge | MYSELF | ALL | 25 | 0 | 30 | 0 | 18 | Warrior, Gladiator, Knight, Juggernaut, Dragoon, General, Paladin | BareHAND, 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP, 2H_TRUMP, WAND, STAFF |  |  | Increases your Attack Speed. |
| 100052001 | Raging Soul | MYSELF | ALL | 35 | 0 | 60 | 0 | 35 | Gladiator, Juggernaut, Dragoon | ALL |  |  | Sacrifices your Defense to focus on Attack Power. |
| 100053001 | Shieldbearer | MYSELF | ALL | 35 | 0 | 60 | 0 | 35 | Knight, General, Paladin | ALL | ✓ |  | Can only be used when a shield is equipped. Sacrifices your Attack Power to focus on Defense. |
| 100054001 | Concentration | MYSELF | ALL | 18 | 0 | 20 | 0 |  | ALL | ALL |  | Brutal Strike | Accuracy increases for your next attack as the result of boosted concentration. |
| 100055001 | Third Eye | PARTY_ALL | ALLY | 48 | 0.5 | 1.5 | 2500 | 28 | Agent, Assassin, Disturbance | ALL |  |  | Increases the Accuracy of all party members. |
| 100055002 | Third Eye | MYSELF | ALLY | 0 | 0.5 | 1.5 | 2500 |  | any | ALL |  |  | Increases the Accuracy of all party members. |
| 100056001 | Misdirection | MYSELF | ALL | 10 | 0 | 60 | 0 |  | ALL | ALL |  | Ossify | Distracts the enemy, causing them to lose you as their target. Effect only works in PvP. |
| 100057001 | Ossify | TOGGLE | ALL | 24 | 0 | 30 | 0 |  | ALL | ALL |  |  | Immune to Trip, Movement Speed reduction and movement restriction, but Attack Power reduced. |
| 100058001 | Desperado | MYSELF | ALL | 39 | 0 | 35 | 0 | 45 | Juggernaut | ALL |  | Skill Focus | Increases Attack Power, but also increases the damage you take. The effect ends once you make an attack. |
| 100059001 | Equine Charge | MYSELF | ALL | 19 | 0 | 9 | 0 | 45 | Dragoon | LANCE, POLE_ARM |  | Charge | Uses Momentum to perform a powerful charge. Can only be used while on horseback. |
| 100059002 | Equine Charge | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | LANCE, POLE_ARM |  |  |  |
| 100059003 | Equine Charge | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | LANCE, POLE_ARM |  |  |  |
| 100059004 | Equine Charge | BREATH | ENEMY | 0 | 0 | 0 | 0 |  | any | LANCE, POLE_ARM |  |  |  |
| 100060001 | Strong Stance | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | Paladin | any | ✓ | Defensive Attack | Allows you to block magical damage when Blocking, and prevents Knockback. |
| 100061001 | Skill Focus | MYSELF | ALL | 3 | 0 | 0 | 0 | 50 | Juggernaut | ALL |  |  | Your Skill Cooldown Rate is reduced by half at the cost of losing 30% of your LP. |
| 100091001 | Brewer | PASSIVE | ALL | 0 | 0 | 0 | 0 | 12 | Warrior, Gladiator, Knight, Juggernaut, Dragoon, General, Paladin | ALL |  | Lunge | Increases the effectiveness of potions. |
| 100101001 | Slash | ENEMY | ENEMY | 10 | 0 | 10 | 0 |  | ALL | 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP, 2H_TRUMP, WAND, STAFF |  | Bash | A combo skill that strikes with a flurry of attacks, preventing the enemy from evading. |
| 100102001 | Brutal Strike | ENEMY | ENEMY | 14 | 0 | 10 | 0 |  | ALL | 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP, 2H_TRUMP, WAND, STAFF |  | Sword Mastery | Launches a powerful attack that hits regardless of the enemy's armor. This is a combo skill. |
| 100103001 | Leg Sweep | ENEMY | ENEMY | 21 | 0 | 10 | 0 | 20 | Gladiator, Juggernaut, Dragoon | 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP, 2H_TRUMP, WAND, STAFF |  | War Cry | Attacks the enemy's legs, slowing their movements. |
| 100103050 | Leg Sweep | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP, 2H_TRUMP, BOW, CROSSBOW, WAND, STAFF |  |  | Leg Sweep Dummy |
| 110101001 | Slice | ENEMY | ENEMY | 15 | 0 | 10 | 0 |  | ALL | 1H_SWORD, LANCE, 1H_AXE, 1H_BLUNT, 1H_TRUMP, WAND |  | Whirling Strike | A combo skill that strikes the enemy with two rapid cuts. |
| 110101002 | Dice | ENEMY | ENEMY | 15 | 0 | 10 | 0 |  | ALL | 1H_SWORD, 2H_SWORD, LANCE, 1H_AXE, 1H_BLUNT, 1H_TRUMP, WAND |  |  | Strikes with three rapid cuts, which can cause your opponent to Bleed. |
| 110102001 | Sword Mastery | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | ALL | 1H_SWORD, 2H_SWORD, 1H_TRUMP |  | Dice | Increases the damage done when you use a skill with a sword. |
| 111201001 | Bash | ENEMY | ENEMY | 18 | 0 | 10 | 0 |  | ALL | 2H_SWORD, POLE_ARM, 1H_AXE, 2H_AXE, 2H_BLUNT |  | Misdirection | Hits your opponent hard, inflicting both the Knockback and Stun effects. |
| 121701001 | Spear Volley | BOLT | ENEMY | 24 | 1 | 30 | 2500 |  | ALL | LANCE, POLE_ARM |  | Quadruple Stab | Hurls your spear to attack a distant enemy. |
| 121702001 | Heave | BREATH | ENEMY | 16 | 1 | 15 | 900 |  | ALL | LANCE, POLE_ARM |  | Triple Stab | Thrusts your spear mightily, attacking the enemy in front of you. |
| 121703001 | Triple Stab | ENEMY | ENEMY | 22 | 0 | 30 | 300 |  | ALL | LANCE, POLE_ARM |  | Dismounting Stab | Stabs your opponent rapidly three times. |
| 121703501 | Quadruple Stab | ENEMY | ENEMY | 43 | 0 | 16 | 300 |  | ALL | LANCE, POLE_ARM |  | Horse Assault | You stab at your opponent rapidly four times. If you use it while you're activating Triple Stab, your damage will increase. |
| 121703511 | Quadruple Stab | ENEMY | ENEMY | 0 | 0 | 0 | 300 |  | any | LANCE, POLE_ARM |  |  |  |
| 121703512 | Quadruple Stab | ENEMY | ENEMY | 0 | 0 | 0 | 300 |  | any | LANCE, POLE_ARM |  |  |  |
| 121704001 | Charge | MYSELF | ALL | 41 | 0 | 20 | 0 | 50 | Dragoon | LANCE, POLE_ARM |  |  | Uses Momentum to charge forward. Can only be used while on horseback. |
| 121704002 | Charge | BREATH | ENEMY | 41 | 0 | 20 | 1500 | 50 | any | LANCE, POLE_ARM |  |  |  |
| 121705001 | Dismounting Stab | MYSELF | ALL | 28 | 0 | 90 | 0 |  | ALL | ALL |  | Spear Volley | While under this effect, there is a chance to inflict the Unseat effect when you strike with a physical attack. |
| 121707001 | Horse Assault | ENEMY | ENEMY | 13 | 0 | 7 | 0 |  | ALL | LANCE, POLE_ARM |  |  | When your opponent is mounted, your damage will increase and you are granted a chance to Unseat them. |
| 121707002 | Horse Assault | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | LANCE, POLE_ARM |  |  |  |
| 121707003 | Horse Assault | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | LANCE, POLE_ARM |  |  |  |
| 131201001 | Whirling Strike | RADIATION | ENEMY | 28 | 0 | 15 | 0 |  | ALL | 2H_SWORD |  | Parry | Attacks nearby enemies all at once with a spinning blow. |
| 142001001 | Split | BREATH | ENEMY | 22 | 0 | 20 | 200 |  | ALL | 1H_AXE, 2H_AXE |  | Desperate Strike | A ground-splitting axe attack that strikes the area in front of you. |
| 142002001 | Clobber | ENEMY | ENEMY | 19 | 0 | 25 | 0 |  | ALL | 1H_AXE, 2H_AXE |  | Riposte | Performs a furious attack in an attempt to land a Critical Hit. |
| 142003001 | Grand Shock | BREATH | ENEMY | 38 | 0 | 18 | 200 |  | ALL | 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, WAND, STAFF |  | Stun Hammer | Strikes the ground hard, damaging your opponent with a shockwave that interrupts their spellcasting. |
| 142005001 | Desperate Strike | ENEMY | ENEMY | 36 | 0 | 15 | 0 |  | ALL | 2H_SWORD, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, WAND, STAFF |  |  | Strikes your opponent with a mighty attack that Stuns them. If your attack fails or is blocked, the effect is reversed. |
| 142051001 | Roar | MYSELF | ALL | 30 | 0 | 120 | 0 |  | ALL | 1H_AXE, 2H_AXE |  | Split | Sharpens your nerves and increases your chance to land a Critical Hit. |
| 142501001 | Stun | ENEMY | ENEMY | 15 | 0 | 8 | 0 |  | ALL | 1H_BLUNT, 2H_BLUNT, WAND, STAFF |  | Grand Shock | Stuns your opponent with a powerful strike. |
| 142501101 | Stun Hammer | RADIATION | ENEMY | 30 | 0 | 15 | 0 |  | ALL | 1H_BLUNT, 2H_BLUNT |  | Shatter Armor | Strikes the ground hard and Stuns your surrounding enemies with the resulting shockwaves. |
| 142502001 | Shatter Armor | ENEMY | ENEMY | 30 | 0 | 15 | 0 |  | ALL | 1H_BLUNT, 2H_BLUNT, WAND, STAFF |  | Shield Break | Knocks your opponent's armor off with a powerful attack, and interrupts their spellcasting. |
| 142502050 | Shatter Armor | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | any |  |  |  |
| 142503001 | Shield Break | ENEMY | ENEMY | 22 | 0 | 10 | 0 |  | ALL | 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, WAND, STAFF |  | Subvert | When your opponent is Blocking, you will inflict a Critical Hit and prevent them from using a shield. |
| 142503002 | Shield Break | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, WAND, STAFF |  |  |  |
| 142504001 | Subvert | ENEMY | ENEMY | 69 | 0.5 | 25 | 0 |  | ALL | BareHAND, 1H_BLUNT, 2H_BLUNT |  |  | Destroys your opponent from within. The higher their Defense, the more damage they take. |
| 161201001 | Parry | MYSELF | ALL | 9 | 0.5 | 10 | 0 |  | ALL | 2H_SWORD, POLE_ARM, 2H_AXE, 2H_BLUNT, 2H_TRUMP |  | Concentration | Knocks aside your opponent's attack, leaving them wide open. |
| 161202001 | Riposte | MYSELF | ALL | 12 | 0.5 | 10 | 0 |  | ALL | 2H_SWORD, POLE_ARM, 2H_AXE, 2H_BLUNT, 2H_TRUMP |  | Roar | Knocks aside your opponent's attack, allowing you to follow up with a counter-attack. |
| 161202050 | Counter | ENEMY | ALL | 0 | 0 | 0 | 0 |  | any | 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP, 2H_TRUMP, BOW, CROSSBOW, WAND, STAFF | ✓ |  | Counter Dummy |
| 168001001 | Blocking | TOGGLE_RADIATION | ALLY | 5 | 0 | 2 | 0 |  | ALL | any | ✓ | Shield Bash | Quickly raises your shield, greatly reducing the amount of physical damage you take. |
| 168001002 | Deflect | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | General | ALL |  | Bore Brunt | If you are hit with a charge attack while you are Blocking, you will deflect the damage. |
| 168001003 | Blocking | TOGGLE_RADIATION | ALLY | 5 | 0 | 2 | 0 | 45 | General | any | ✓ | Shield Bash | Quickly raises your shield, greatly reducing the amount of physical damage you take. |
| 168001004 | Blocking | TOGGLE_RADIATION | ALLY | 5 | 0 | 2 | 0 | 45 | Paladin | any | ✓ | Shield Bash | Quickly raises your shield, greatly reducing the amount of physical damage you take. |
| 168002002 | Defensive March | TOGGLE_RADIATION | ALLY | 10 | 0 | 5 | 0 | 45 | General | any | ✓ | Guardian | Allows you to move while your shield is raised. |
| 168002003 | Defensive March | TOGGLE_RADIATION | ALLY | 10 | 0 | 5 | 0 | 45 | Paladin | any | ✓ | Guardian | Allows you to move while your shield is raised. |
| 168002001 | Defensive March | TOGGLE_RADIATION | ALLY | 10 | 0 | 5 | 0 |  | ALL | any | ✓ | Guardian | Allows you to move while your shield is raised. |
| 168003001 | Shield Bash | MYSELF | ALL | 14 | 0 | 10 | 0 |  | ALL | any | ✓ | Parapet | When you are Blocking with your shield, strike back with a powerful blow. |
| 168004001 | Barricade | MYSELF | ALL | 16 | 0 | 10 | 0 |  | any | any | ✓ |  | Only usable while you are Blocking. Allows you to stop a charge attack. |
| 168005001 | Shield Charge | ENEMY | ENEMY | 18 | 0 | 10 | 400 |  | ALL | any | ✓ | Defensive March | Only usable while you are Blocking. You raise your shield and charge forward, knocking aside enemies in your way. |
| 168005050 | Shield Charge | BOLT | ENEMY | 0 | 0 | 0 | 400 |  | any | any |  |  |  |
| 168051001 | Auto-guard | MYSELF | ALL | 20 | 0 | 30 | 0 |  | ALL | any | ✓ | Shield Charge | Automatically defends against attacks as you move. |
| 168051002 | Auto-guard | MYSELF | ALL | 20 | 0 | 30 | 0 |  | ALL | any | ✓ | Shield Charge | Automatically defends against attacks as you move. |
| 168052001 | Parapet | MYSELF | ALL | 25 | 2 | 30 | 0 |  | ALL | ALL |  | Auto-guard | Your Dodge goes down, but you also become harder to hit with a Critical Hit. |
| 168052002 | Parapet | MYSELF | ALL | 25 | 2 | 30 | 0 |  | ALL | ALL |  | Auto-guard | Your Dodge goes down, but you also become harder to hit with a Critical Hit. |
| 168053001 | Eternal Dirge | TOGGLE_RADIATION | ALL | 74 | 0 | 20 | 0 |  | ALL | ALL |  |  | Prevents players in the area of effect from using skills. |
| 168054001 | Divine Protection | TOGGLE | ALL | 60 | 0 | 20 | 0 |  | ALL | any | ✓ |  | This can be used while Blocking. Prevents movement, but grants immunity to negative status effects and evil magic. |
| 168055001 | Defensive Attack | PASSIVE | ALL | 0 | 0 | 0 | 0 | 50 | Paladin | ALL |  |  | Your limits when in Defensive March are released. |
| 213601001 | Flaming Arrow | BOLT | ENEMY | 12 | 0 | 30 | 4000 |  | ALL | BOW, CROSSBOW |  | Cobra Arrow | Launches a fiery arrow. |
| 213602001 | Cobra Arrow | BOLT | ENEMY | 12 | 0 | 30 | 4000 |  | ALL | BOW, CROSSBOW |  | Arrow Rain | Fires a venomous arrow, Poisoning your opponent. |
| 213603001 | Arrow Rain | SPHERE | ENEMY | 15 | 1 | 5 | 5000 |  | ALL | BOW |  | Silence Arrow | Aims for a point in the air, and unleashes a rain of arrows in the area of effect. |
| 213603002 | Arrow Storm | ENEMY | ENEMY | 15 | 2 | 5 | 5000 |  | ALL | BOW |  | Pinning Arrow | Unleashes a storm of arrows on the area of effect, inflicting continuous damage. |
| 213603003 | Arrow Storm | SPHERE | ENEMY | 0 | 0 | 0 | 5000 |  | ALL | BOW |  |  | Unleashes a storm of arrows on the area of effect, inflicting continuous damage. |
| 213603501 | Silence Arrow | BOLT | ENEMY | 33 | 0 | 10 | 4000 |  | ALL | BOW, CROSSBOW |  | Arrow Storm | Fires an arrow that has a chance of inflicting the enemy with Silence. |
| 213603511 | Silence Arrow | ENEMY | ENEMY | 0 | 0 | 0 | 4000 |  | any | BOW, CROSSBOW |  |  |  |
| 213603521 | Silence Arrow | ENEMY | ENEMY | 0 | 0 | 0 | 4000 |  | any | BOW, CROSSBOW |  |  |  |
| 213605001 | Sniper Nest | TOGGLE | ALL | 45 | 2 | 5 | 0 | 45 | Vigilance | BOW, CROSSBOW |  | Kindling Arrow | Attack Power, Accuracy, and ranged attack distance increase, but unable to move. Toggle on/off for effect. |
| 213606001 | Watchful Eye | TOGGLE | ALL | 44 | 0.5 | 20 | 0 | 45 | Predator | ALL |  | Arrow Fusillade | Allows you to spot Hiding enemies within your area of effect. Your damage increases, but you are unable to move. |
| 213607001 | Pinning Arrow | ENEMY | ENEMY | 49 | 0 | 30 | 0 |  | ALL | BOW, CROSSBOW |  |  | Immobilizes the enemy when struck from behind. A hit from another attack ends this effect. |
| 213607002 | Pinning Arrow | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 213608001 | Kindling Arrow | POINT | ALL | 41 | 1 | 15 | 4000 | 50 | Vigilance | BOW |  |  | Sets the area of effect ablaze with a fiery arrow, creating a field of flame. |
| 213608002 | Kindling Arrow | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | BOW |  |  |  |
| 213700501 | Charge Shot | ENEMY | ENEMY | 18 | 0 | 30 | 4000 |  | ALL | BOW |  | Multi Shot | Fires a powerful arrow that will Knockback your target. |
| 213700550 | Charge Shot | BOLT | ENEMY | 0 | 0 | 0 | 4000 |  | any | any |  |  |  |
| 213701001 | Multi Shot | ENEMY | ENEMY | 20 | 0 | 30 | 1250 |  | ALL | CROSSBOW |  |  | Fires arrows in five directions at once. |
| 213702001 | Rapid Fire | MYSELF | ALL | 45 | 0 | 45 | 0 | 35 | Archer, Vigilance, Predator | CROSSBOW |  |  | Allows you to fire bolts in rapid succession by darting about. |
| 213703001 | Arrow Fusillade | MYSELF | ALL | 54 | 0 | 90 | 0 | 50 | Predator | CROSSBOW |  |  | When using a crossbow, range increases and you are granted the ability to fire twice in a row |
| 213703002 | Double Missiles | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | BOW, CROSSBOW |  |  | When using a crossbow, range increases and you are granted the ability to fire twice in a row |
| 220001001 | Toxify | MYSELF | ALL | 15 | 2 | 10 | 0 |  | ALL | ALL |  | Serum | Consumes a Venom to coat your weapons. |
| 220001002 | Toxic Aura | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  | Surveillance | Increases Elemental Damage while Toxify is active. |
| 220001003 | Toxify | MYSELF | ALL | 15 | 2 | 10 | 0 |  | ALL | ALL |  | Serum | Consumes a Venom to coat your weapons. |
| 220002001 | Poison-Making | MYSELF | ALL | 3 | 1 | 0 | 0 |  | ALL | ALL |  | Toxify | Consumes a Deadly Nightshade and a Container to create Venom. |
| 220003001 | Serum | MYSELF | ALL | 3 | 1 | 0 | 0 |  | ALL | ALL |  | Potion Crafting | Consumes an Antidote Herb and a Container to create an Antidote. |
| 220004001 | Potion Crafting | MYSELF | ALL | 3 | 0 | 0 | 0 |  | ALL | ALL |  | Befuddle | Consumes a Moonlight Herb, an Aquilegia, and a Container to create a Mysterious Potion. |
| 220005001 | Magical Protection | ALLY | ALLY | 12 | 1.5 | 0 | 2000 |  | any | ALL |  |  | Increases your Magic Resistance, but decreases Defense. |
| 220006001 | Befuddle | MYSELF | ALL | 31 | 0 | 0 | 0 |  | ALL | ALL |  | Toxic Aura | Slows down the Casting Speed of any opponent you strike with a physical attack. Consumes one Venom. |
| 220006002 | Befuddle | ALLY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 220007001 | Surveillance | MYSELF | ALL | 44 | 0.5 | 20 | 0 |  | ALL | ALL |  |  | Allows you to spot traps that your enemies have set. |
| 230001001 | Hiding | TOGGLE | ALL | 24 | 0 | 3 | 0 | 18 | Scout, Archer, Agent, Vigilance, Predator, Assassin, Disturbance | ALL |  |  | Enables you to camouflage your appearance where you stand. |
| 230001002 | Hiding | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 230002001 | Cloaking | TOGGLE | ALL | 45 | 2 | 30 | 0 | 20 | Agent, Assassin, Disturbance | ALL |  | Third Eye | Enables you to enter a Hiding state that allows movement. |
| 230002002 | Furtive Steps | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | Assassin | ALL |  | Counterpunch | Removes the Movement Speed reduction while Cloaking, and increases the MP Recovery Rate slightly. |
| 230002003 | Treachery | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | Disturbance | ALL |  |  | Prevents you from dropping out of the Hiding state after striking an enemy. |
| 230002004 | Cloaking | TOGGLE | ALL | 45 | 2 | 30 | 0 | 45 | Assassin | ALL |  |  | Enables you to enter a Hiding state that allows movement. |
| 230002005 | Cloaking | TOGGLE | ALL | 45 | 2 | 30 | 0 | 45 | Disturbance | ALL |  |  | Enables you to enter a Hiding state that allows movement. |
| 233001001 | Blindside | ENEMY | ENEMY | 15 | 0 | 5 | 200 |  | ALL | 1H_TRUMP, 2H_TRUMP |  | Pierce Armor | Prevents you from dropping out of the Hiding state after striking the enemy. |
| 233200101 | Counterpunch | MYSELF | ALL | 37 | 0 | 90 | 0 | 50 | Assassin | 2H_TRUMP |  |  | When using martial arts, you will strike with a weaker follow-up attack |
| 233002001 | Pierce Armor | ENEMY | ENEMY | 15 | 0 | 10 | 200 |  | ALL | 1H_TRUMP, 2H_TRUMP |  | Double-Cross | An attack that aims for openings in your opponent's armor. Especially effective against enemies affected by Trip. |
| 233003001 | Backstab | ENEMY | ENEMY | 15 | 0 | 30 | 200 |  | ALL | 1H_TRUMP, 2H_TRUMP |  | Dagger Throw | A powerful attack that targets your opponent's back. |
| 233005001 | Double-Cross | ENEMY | ENEMY | 58 | 0.2 | 55 | 0 |  | ALL | ALL |  |  | After striking your opponent in the back, all Skill Cooldowns finish, excluding this one. |
| 233005002 | Double-Cross | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | 2H_TRUMP |  |  | When using martial arts, you will strike with a weaker follow-up attack |
| 233006001 | Vendetta | TOGGLE | ALL | 10 | 0 | 10 | 0 |  | ALL | ALL |  |  | When your attacks are dodged, you lose 5% of your health and receive the Raging Soul skill effect. |
| 233006002 | Vendetta | MYSELF | ALL | 0 | 0 | 10 | 0 |  | any | ALL |  |  |  |
| 233101001 | Dagger Throw | BOLT | ENEMY | 10 | 0 | 5 | 1500 |  | ALL | 1H_TRUMP |  | Rush | Quickly throws daggers at your opponent. |
| 233151001 | Rush | MYSELF | ALL | 30 | 0 | 60 | 0 |  | ALL | 1H_TRUMP, 2H_TRUMP |  | Blindside | Each attack will hit twice, but damage taken will be increased. |
| 240001001 | Tangled Legs | POINT | ENEMY | 20 | 1.5 | 3 | 200 |  | ALL | ALL |  | Plant Mine | Sets a trap that grabs your opponent's legs and renders them immobile. This consumes one Trap. |
| 240001050 | Tangled Legs | CIRCLE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Tangled Legs Dummy |
| 240002001 | Plant Mine | POINT | ENEMY | 30 | 1.5 | 3 | 200 |  | ALL | ALL |  | Worm Bomb | Sets a trap that explodes when stepped on, inflicting damage to the surrounding area. This consumes one Trap. |
| 240002050 | Plant Mine | CIRCLE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Plant Mine Dummy |
| 240002002 | Plant Mine | POINT | ENEMY | 30 | 1.5 | 3 | 200 | 50 | Disturbance | ALL |  | Worm Bomb | Sets a trap that explodes when stepped on, inflicting damage to the surrounding area. This consumes one Trap. |
| 240002051 | Plant Mine | CIRCLE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 240003001 | Disarm | POINT | ALL | 10 | 1 | 10 | 700 |  | ALL | ALL |  | Tangled Legs | Disarms every trap in the area of effect, regardless of who set it. |
| 240003002 | Disarm | SPHERE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Disarms every trap in the area of effect. |
| 240004001 | Spring Trap | POINT | ENEMY | 13 | 1 | 0 | 100 |  | any | ALL |  |  | Sets a trap that launches its victim far away. This consumes one Trap. |
| 240004050 | Spring Trap | CIRCLE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Spring Trap Dummy |
| 240005001 | Worm Bomb | POINT | ENEMY | 33 | 3 | 5 | 300 |  | ALL | ALL |  | Safe Zone | Unleashes a worm that moves forward in a straight line, exploding whatever it touches. This consumes two Traps. |
| 240005002 | Worm Bomb | BOLT | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Unleashes a worm that moves forward in a straight line, exploding whatever it touches. This consumes two Traps. |
| 240005003 | Worm Bomb | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Unleashes a worm that moves forward in a straight line, exploding whatever it touches. This consumes two Traps. |
| 240006001 | Safe Zone | POINT | ALL | 46 | 1.5 | 8 | 200 |  | ALL | ALL |  | Stone Prison | When a player enters the area of effect, any effects on them caused by Field Skills will be dispelled. |
| 240008001 | Mind Warp | POINT | ENEMY | 48 | 1.5 | 3 | 200 |  | ALL | ALL |  |  | Sets a trap that removes some of the target's MP. This consumes one Trap. |
| 240008002 | Mind Warp | CIRCLE | ENEMY | 0 | 0 | 0 | 0 |  | Warrior, Gladiator, Knight, Scout, Archer, Agent, Acolyte, Priest, Ascetic, Mage, Wizard, Darklore | ALL |  |  |  |
| 240009001 | Mine Boost | PASSIVE | ALL | 0 | 0 | 0 | 0 | 50 | Disturbance | ALL |  |  | Increases the maximum number of Traps and the amount of damage done by Plant Mine. Based on level of Trapping Expertise. |
| 240010001 | Stone Prison | POINT | ENEMY | 48 | 1.5 | 3 | 200 |  | ALL | ALL |  | Mind Warp | Traps players behind a solid wall. Can only be triggered by mounted players. This consumes one Trap. |
| 240010002 | Stone Prison | CIRCLE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 240010003 | Stone Prison | POINT | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Traps players behind a solid wall. Can only be triggered by mounted players. This consumes one Trap. |
| 260001001 | Backstep | MYSELF | ALL | 5 | 0 | 3 | 0 |  | ALL | ALL |  |  | Quickly move backwards. |
| 260002001 | Invigorate | MYSELF | ALL | 16 | 0 | 10 | 0 | 12 | Scout, Archer, Agent, Vigilance, Predator, Assassin, Disturbance | ALL |  | Hiding | Increases your Movement Speed. |
| 260003001 | Dash | MYSELF | ALL | 18 | 0 | 30 | 0 |  | ALL | ALL |  | Quick Step | Momentarily increases your Movement Speed, allowing you to move very quickly. |
| 260003002 | Dash | MYSELF | ALL | 18 | 0 | 30 | 0 |  | ALL | ALL |  | Quick Step | Momentarily increases your Movement Speed, allowing you to move very quickly. |
| 260004001 | Tangled Fingers | ENEMY | ENEMY | 22 | 0 | 30 | 2500 |  | ALL | ALL |  | Reinforce | Reduces your opponent's Accuracy. |
| 260005001 | Quick Step | MYSELF | ALL | 35 | 0 | 90 | 0 |  | ALL | ALL |  | Tangled Fingers | Increases your Dodge. |
| 260006001 | Speedy Gale | PARTY_ALL | ALLY | 55 | 0.5 | 1.5 | 2500 | 28 | Ascetic, Monk, Exorcist | ALL |  |  | Increases the Dodge of all party members. |
| 260006002 | Speedy Gale | MYSELF | ALLY | 55 | 0.5 | 1.5 | 2500 |  | any | ALL |  |  | Increases the Dodge of all party members. |
| 260007001 | Reinforce | PASSIVE | ALLY | 0 | 0 | 0 | 0 |  | ALL | ALL |  | Avoidance | Trip Resistance, Stun Resistance, and Freeze Resistance +1%. |
| 260008001 | Avoidance | MYSELF | ALLY | 38 | 0.5 | 30 | 0 |  | ALL | ALL |  | Intuition | While this is in effect, your Dodge increases. The effect ends when you are hit by two physical attacks. |
| 260009001 | Intuition | PASSIVE | ALLY | 0 | 0 | 0 | 0 |  | ALL | ALL |  | Bolster | Gives you a chance to evade your enemy's magic. |
| 260010001 | Bolster | ALLY | ALLY | 29 | 1 | 15 | 2500 |  | ALL | ALL |  |  | The targeted player gains the Dash skill effect. |
| 300001001 | Physical Barrier | ENEMY | ALL | 128 | 2 | 10 | 1500 |  | ALL | ALL |  |  | Places a barrier on the target that completely protects them against a single physical attack. |
| 300002001 | Magical Barrier | ENEMY | ALL | 128 | 2 | 10 | 1500 |  | ALL | ALL |  |  | Places a barrier on the target that completely protects them against a single magical attack. |
| 300003001 | Merciful Blessing | PASSIVE | ALL | 0 | 0 | 0 | 0 | 50 | Cleric | ALL |  |  | Draws out LP recovery skills through the power of great mercy. |
| 300004001 | Mental Aid | ALLY | ALL | 14 | 2 | 60 | 2500 |  | ALL | ALL |  |  | Dispels a single Disorder. |
| 300004002 | Mental Aid | ALLY | ALL | 14 | 0 | 60 | 2500 |  | ALL | ALL |  |  | Dispels a single Disorder. |
| 300004003 | Mental Aid | ALLY | ALL | 14 | 0 | 60 | 2500 |  | ALL | ALL |  |  | Dispels a single Disorder. |
| 300004004 | Mental Aid | ALLY | ALL | 14 | 0 | 60 | 2500 |  | ALL | ALL |  |  | Dispels a single Disorder. |
| 310001001 | First Aid | ALLY | ALLY | 28 | 1 | 4 | 3500 |  | ALL | ALL |  | Cleanse | Quickly heals a little bit of your target's LP. |
| 310001002 | First Aid | ALLY | ALLY | 28 | 0 | 4 | 3500 | 50 | Cleric | ALL |  | Cleanse | Quickly heals a little bit of your target's LP. |
| 310001003 | First Aid | ALLY | ALLY | 28 | 0 | 4 | 3500 | 50 | Cleric | ALL |  |  | Quickly heals a little bit of your target's LP. |
| 310002001 | Regenerate | ALLY | ALLY | 40 | 1.5 | 5 | 2500 |  | ALL | ALL |  | Vivify | Imbues your target with restorative magic, healing them continually for a set period of time. |
| 310002002 | Regenerate | ALLY | ALLY | 40 | 1.5 | 5 | 2500 |  | ALL | ALL |  |  | Imbues your target with restorative magic, healing them continually for a set period of time. |
| 310003001 | Revive | ALLY | ALLY | 65 | 5 | 30 | 2500 | 35 | Priest, Cleric, Enchanter | ALL |  |  | Revives someone who has been defeated in battle. This consumes three Holy Waters. |
| 310004001 | Heal | ALLY | ALLY | 62 | 2 | 3 | 3500 | 18 | Acolyte, Priest, Ascetic, Cleric, Enchanter, Monk, Exorcist | ALL |  |  | Restores your target's LP using healing magic. |
| 310004002 | Heal | ALLY | ALLY | 62 | 2 | 3 | 3500 | 50 | Cleric | ALL |  |  | Restores your target's LP using healing magic. |
| 310004003 | Heal | ALLY | ALLY | 62 | 2 | 3 | 3500 |  | Cleric | ALL |  |  | Restores your target's LP using healing magic. |
| 310011001 | Cleanse | ALLY | ALLY | 15 | 1 | 3 | 3500 |  | ALL | ALL |  | Regenerate | Cures your target of Poison effects. |
| 310011002 | Cleanse | ALLY | ALLY | 15 | 0 | 3 | 3500 |  | ALL | ALL |  |  | Cures your target of Poison effects. |
| 310012001 | Vivify | ALLY | ALLY | 18 | 1 | 3 | 3500 |  | ALL | ALL |  | Restoration | Cures Sleep, Stun, and Freeze effects. |
| 310012002 | Vivify | ALLY | ALLY | 18 | 1 | 3 | 3500 |  | ALL | ALL |  | Restoration | Cures Sleep, Stun, and Freeze effects. |
| 310014001 | Purify | ALLY | ALLY | 76 | 1.5 | 35 | 2500 |  | ALL | ALL |  |  | Cures your target of all negative status effects, and increases their resistance to status effects. |
| 310014002 | Purify | ALLY | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 310021001 | Healing Aura | PARTY_ALL | ALLY | 256 | 1 | 30 | 3500 |  | ALL | ALL |  | Purify / Peaceful Hymn | Restores LP for all party members. |
| 310021002 | Healing Aura | PARTY_ALL | ALLY | 256 | 1 | 30 | 3500 | 50 | Cleric | ALL |  | Purify / Peaceful Hymn | Restores LP for all party members. |
| 310022001 | Restoration | PARTY_ALL | ALLY | 90 | 3 | 20 | 3500 |  | ALL | ALL |  | Healing Aura | Continuously restores LP for all party members. |
| 310023001 | Sanctuary | POINT | ALL | 87 | 5 | 60 | 1000 | 45 | Cleric | ALL |  |  | Creates a consecrated area, restoring LP to all players within. |
| 310023002 | Sanctuary | SPHERE | ALL | 0 | 0 | 0 | 1000 |  | any | ALL |  |  |  |
| 320001001 | War Cry | PARTY_ALL | ALLY | 31 | 0.5 | 1.5 | 1500 | 28 | Gladiator, Juggernaut, Dragoon | ALL |  | Raging Soul | Raises the physical abilities of all party members, increasing their Attack Power. |
| 320001050 | War Cry | ALLY | ALLY | 16 | 0.5 | 1.5 | 2500 | 0 | any | ALL |  |  | Raises your Attack. |
| 320002001 | Tranquil Mind | PARTY_ALL | ALLY | 50 | 5 | 20 | 3500 | 20 | Priest, Cleric, Enchanter | ALL |  |  | Increases the MP Recovery Rate for all party members. |
| 320003001 | Group Barrier | PARTY_ALL | ALLY | 70 | 1 | 1.5 | 3500 |  | ALL | ALL |  | Aqua Elymus | Reduces all incoming damage for all party members. |
| 320003002 | Group Barrier | MYSELF | ALL | 0 | 1 | 1.5 | 0 |  | any | ALL |  |  | Cannot use at this time. |
| 320004001 | Accelerate | ALLY | ALLY | 16 | 0.5 | 1.5 | 2500 | 28 | Archer, Vigilance, Predator | ALL |  | Rapid Fire | Grants you the blessing of the wind, increasing your Movement Speed. |
| 320004002 | Accelerate | ALLY | ALLY | 16 | 0.5 | 1.5 | 2500 |  | any | ALL |  |  | Grants you the blessing of the wind, increasing your Movement Speed. |
| 320004051 | Accelerate | ALLY | ALLY | 16 | 0.5 | 1.5 | 2500 |  | any | ALL |  |  | Grants you the blessing of the wind, increasing your Movement Speed. |
| 320005001 | Divine Aid | PARTY_ALL | ALLY | 89 | 4 | 1.5 | 2500 | 28 | Priest, Cleric, Enchanter | ALL |  | Revive | Grants you the blessing of health, greatly increasing the LP of all party members. |
| 320005051 | Divine Aid | ALLY | ALLY | 0 | 0 | 0 | 2500 |  | any | ALL |  |  | Grants you the blessing of health, greatly increasing the LP of all party members. |
| 320006001 | Saltio | ALLY | ALLY | 37 | 0 | 5 | 2500 |  | ALL | ALL |  | Battle Prayer | Increases the Casting Speed of any skill being used by a target other than yourself. |
| 320006002 | Saltio | ALLY | ALLY | 37 | 0 | 5 | 2500 |  | ALL | ALL |  |  | Increases the Casting Speed of your own skills. |
| 320006051 | Saltio | ALLY | ALLY | 37 | 0 | 5 | 2500 |  | any | ALL |  |  | Increases the effect of the soul affixed in the adjacent slot of the same item. |
| 320006052 | Saltio | ALLY | ALLY | 0 | 0 | 0 | 2500 |  | any | ALL |  |  | Increases the effect of the soul affixed in the adjacent slot of the same item. |
| 320007001 | Velox | ALLY | ALLY | 26 | 0.5 | 1.5 | 3500 |  | ALL | ALL |  | Lapis Medio | Increases the Attack Speed of your target. |
| 320007050 | Velox | ALLY | ALLY | 0 | 0.5 | 1.5 | 3500 | 0 | General, Archer | ALL |  | Lapis Medio | Increases the Attack Speed of your target. |
| 320008001 | Lapis Medio | PARTY_ALL | ALLY | 22 | 0.5 | 1.5 | 2500 |  | ALL | ALL |  | Impedimenta | Increases the Defense of all party members. |
| 320009001 | Impedimenta | ENEMY | ENEMY | 33 | 1.5 | 10 | 2000 |  | ALL | ALL |  | Group Barrier | Reduces your target's Movement Speed. |
| 320010001 | Aqua Elymus | MYSELF | ALL | 4 | 1 | 0 | 0 |  | ALL | ALL |  | Saltio | Consumes a Container to create Holy Water. |
| 320011001 | Enchantment | ALLY | ALLY | 68 | 0.5 | 1.5 | 2500 | 45 | Enchanter | ALL |  | Karmic Aura | Places an effect on a targeted ally player, granting them increased Elemental Damage and Magical Attack Power. |
| 320012001 | Battle Prayer | ALLY | ALLY | 78 | 0.5 | 1.5 | 2500 |  | ALL | ALL |  | Sage's Song | Increases the target's Strength, Agility, and Intelligence. |
| 320013001 | Karmic Aura | TOGGLE | ALL | 0 | 0 | 0 | 0 | 50 | Enchanter | ALL |  |  | Grants positive status effects to all allies within the area of effect. Toggle on/off for effect. |
| 320091001 | Meditation | PASSIVE | ALL | 0 | 0 | 0 | 0 | 12 | Acolyte, Priest, Ascetic, Cleric, Enchanter, Monk, Exorcist | ALL |  | Heal | Unifies your spirit and increases your MP Recovery Rate. |
| 320092001 | Sound Mind | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | Monk | ALL |  | Paralyzing Bond | Reduces the duration of Disorders. |
| 330001001 | Pure Arrow | BOLT | ENEMY | 18 | 1 | 5 | 3500 |  | ALL | ALL |  | Elemental Absorption | Fires an arrow made out of light. Highly effective against demons and the undead. |
| 330002001 | Elemental Absorption | MYSELF | ALL | 60 | 0.8 | 10 | 0 |  | ALL | ALL |  | Bless Weapon | Reduces the damage from Fire, Ice, and Lightning magic. |
| 330002002 | Elemental Absorption | MYSELF | ALL | 60 | 0.8 | 10 | 0 |  | ALL | ALL |  | Bless Weapon | Reduces the damage from Fire, Ice, and Lightning magic. |
| 330003001 | Remedium | ALLY | ALL | 26 | 1 | 5 | 2500 |  | ALL | ALL |  | Holy Rays | Dispels a negative status effect through the power of a blessing. |
| 330003002 | Remedium | ALLY | ALL | 26 | 1 | 5 | 2500 |  | ALL | ALL |  | Holy Rays | Dispels a negative status effect through the power of a blessing. |
| 330004001 | Providence | PARTY_ALL | ALLY | 62 | 0.5 | 1.5 | 2500 | 28 | Knight, General, Paladin | ALL |  | Shieldbearer | Increases the Magic Resistance of all party members by increasing their faith. |
| 330004002 | Providence | MYSELF | ALLY | 0 | 0.5 | 1.5 | 2500 |  | any | ALL |  |  | Increases the Magic Resistance of all party members by increasing their faith. |
| 330005001 | Mana Restore | ALLY | ALLY | 32 | 1.5 | 10 | 1250 | 20 | Ascetic, Monk, Exorcist | ALL |  | Speedy Gale | Restores the target's MP by invigorating their magical power. |
| 330005002 | Mana Restore | ALLY | ALLY | 32 | 1.5 | 10 | 1250 | 20 | Ascetic, Monk, Exorcist | ALL |  | Speedy Gale | Restores the target's MP by invigorating their magical power. |
| 330051001 | Bless Weapon | ALLY | ALLY | 30 | 1.5 | 1.5 | 2500 |  | ALL | ALL |  | Remedium | Grants a Light aura to the target's weapon. |
| 330061001 | Holy Rays | POINT | ALLY | 132 | 6 | 60 | 1250 |  | ALL | ALL |  | Banish / Devotion | Creates pillars of light surrounding the caster, damaging one's enemies. |
| 330061002 | Holy Rays | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Creates pillars of light surrounding the caster, damaging one's enemies. |
| 330071001 | Mana Swap | ENEMY | ALL | 16 | 2 | 10 | 1250 | 45 | Exorcist | ALL |  | Soul Swap | Exchanges your MP with your target's. |
| 330072001 | Soul Swap | ENEMY | ALL | 21 | 1 | 10 | 2500 | 50 | Exorcist | ALL |  |  | Exchanges your status effects with your target's. |
| 330081001 | Banish | POINT | ALL | 41 | 5 | 10 | 1000 |  | ALL | ALL |  | Silent Void | Eliminates any summoned creatures within a certain radius around the caster. |
| 330081002 | Banish | SPHERE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 330091001 | Silent Void | POINT | ALL | 93 | 5 | 12 | 1000 |  | ALL | ALL |  |  | Disables Field Skills and prevents targeting areas within the area of effect. |
| 330091002 | Silent Void | POINT | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Disables Field Skills and prevents targeting areas within the area of effect. |
| 330101001 | Devotion | PARTY_SINGLE | ALLY | 50 | 3 | 0.5 | 2500 |  | ALL | ALL |  |  | Supplies the MP for any skills used by the target. This can be used on up to four people. |
| 340003001 | Peaceful Hymn | TOGGLE | ALLY | 33 | 0 | 5 | 0 |  | ALL | ALL |  |  | A song that makes players within the area of effect immune to damage lower than a set amount. Toggle on/off for effect. |
| 340003002 | Peaceful Hymn | SPHERE | ALLY | 33 | 0 | 5 | 0 |  | any | ALL |  |  |  |
| 340003003 | Peaceful Hymn | ALLY | ALLY | 33 | 0 | 5 | 0 |  | any | ALL |  |  |  |
| 340004001 | Sage's Song | TOGGLE | ALLY | 33 | 0 | 5 | 0 |  | ALL | ALL |  |  | Attack spells are stronger and Skill Cooldown is shortened for players in the area of effect. Toggle on/off for effect. |
| 340004002 | Sage's Song | SPHERE | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 340004003 | Sage's Song | ALLY | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 340004004 | Sage's Song | ALLY | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 340001001 | Minstrel's Song | TOGGLE | ALLY | 30 | 0 | 5 | 0 |  | ALL | ALL |  | Luminous Chant | A song that increases the Accuracy and Dodge of players within the area of effect. Toggle on/off for effect. |
| 340001002 | Minstrel's Song | SPHERE | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 340001003 | Minstrel's Song | ALLY | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 340001004 | Minstrel's Song | TOGGLE | ALLY | 30 | 0 | 5 | 0 |  | ALL | ALL |  | Luminous Chant | A song that increases the Accuracy and Dodge of players within the area of effect. Toggle on/off for effect. |
| 340001005 | Minstrel's Song | SPHERE | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 340001006 | Minstrel's Song | ALLY | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 340002001 | Luminous Chant | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Grants the ability to move while using Hymn skills. Based on level of Hymn Expertise. |
| 350001001 | Paralyzing Bond | ENEMY | ENEMY | 47 | 0 | 30 | 0 | 50 | Monk | ALL |  |  | When you strike from behind, both you and your target cease moving. |
| 350001002 | Paralyzing Bond | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | When you strike from behind, both you and your target cease moving. |
| 410000101 | Magical Aid | MYSELF | ALL | 56 | 2.5 | 15 | 0 | 45 | Warlock | ALL |  |  | Amplifies the effect of the next magic spell you use. |
| 410000201 | Teleport | MYSELF | ALL | 24 | 2 | 300 | 0 | 45 | Conjurer | ALL |  | Supreme Mind | Creates a warp linking your current location with the location saved by the Memorize skill. |
| 410000202 | Teleport | POINT | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 410000203 | Teleport | POINT | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 410000301 | Memorize | MYSELF | ALL | 10 | 1 | 5 | 0 | 45 | Conjurer | ALL |  | Intelletto | Saves a single location to warp to with the Teleport skill. Warping can only be used on certain PvP maps. |
| 410000401 | Intelletto | PASSIVE | ALL | 0 | 0 | 0 | 0 | 50 | Conjurer | ALL |  |  | Increases the number of locations that can be saved by Memorize. Based on level of Invocation Expertise. |
| 410001001 | Fire Bolt | BOLT | ENEMY | 28 | 0.8 | 2 | 2500 | 1 | Mage, Wizard, Darklore, Warlock, Conjurer, Jester, Calamity | ALL |  |  | Launches a fiery arrow at your target. |
| 410002001 | Fire Storm | RADIATION | ENEMY | 100 | 6 | 30 | 0 |  | ALL | ALL |  | Resist Fire | Creates an enveloping hurricane of fire. |
| 410003001 | Resist Fire | ENEMY | ALL | 32 | 1.5 | 3.5 | 1500 |  | ALL | ALL |  | Resist Ice | Increases the target's Fire Resistance, but decreases their Ice and Lightning Resistance. |
| 410004001 | Time Bomb | ENEMY | ENEMY | 61 | 2 | 6 | 2000 |  | ALL | ALL |  | Ice Tempest | Explodes your target after a certain period of time. Damage based on how much time passes before explosion. |
| 410005001 | Meteor Shower | POINT | ALL | 312 | 21 | 20 | 4000 |  | ALL | ALL |  |  | Showers meteors on the designated area, possibly Stunning those in the area of effect. |
| 410005002 | Meteor Shower | BOLT | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 410005003 | Meteor Shower | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 410011001 | Hailstone | BOLT | ENEMY | 18 | 0.3 | 2 | 2500 |  | ALL | ALL |  | Thunder Ball | Launches a mass of ice at your target. |
| 410012000 | Ice Spear | BOLT | ENEMY | 0 | 0 | 0 | 3000 |  | any | ALL |  |  | Dummy |
| 410012001 | Ice Spear | BOLT | ENEMY | 59 | 1.5 | 5 | 3000 |  | ALL | ALL |  | Fire Storm | Launches a sharp ice arrow at your target. |
| 410013001 | Icy Strike | ENEMY | ENEMY | 44 | 0.3 | 12 | 2500 |  | ALL | ALL |  | Wasteland | Quickly strikes your target with ice, inflicting them with the Freeze effect. |
| 410014001 | Ice Storm | POINT | ENEMY | 112 | 7.5 | 20 | 2500 |  | ALL | ALL |  | Time Bomb | Creates a whirling icy vortex that will Knockback the enemy. |
| 410014002 | Ice Storm | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 410014003 | Ice Tempest | POINT | ENEMY | 287 | 7.5 | 20 | 2500 |  | ALL | ALL |  |  | Creates an immense icy vortex that will Knockback the enemy. |
| 410014004 | Ice Tempest | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 410015001 | Resist Ice | ENEMY | ALL | 32 | 1.5 | 3.5 | 1500 |  | ALL | ALL |  | Resist Lightning | Increases your target's Ice Resistance, but reduces their Fire and Lightning Resistance. |
| 410021001 | Shock | ENEMY | ENEMY | 44 | 0.5 | 20 | 2500 | 12 | Mage, Wizard, Darklore, Warlock, Conjurer, Jester, Calamity | ALL |  |  | Strikes your target with lightning and temporarily restricts their movement. |
| 410021002 | Shock | ALLY | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 410022001 | Thunder Ball | BOLT | ENEMY | 50 | 2 | 5 | 3500 |  | ALL | ALL |  | Ice Spear | Expels a mass of lightning into the distance, damaging the target and enemies in the surrounding area. |
| 410022050 | Thunder Ball | SPHERE | ENEMY | 50 | 2 | 5 | 3500 |  | any | ALL |  |  | Expels a mass of lightning into the distance, damaging the target and enemies in the surrounding area. |
| 410023001 | Thunder Crash | ENEMY | ENEMY | 78 | 3.5 | 12 | 3500 | 20 | Wizard, Warlock, Conjurer | ALL |  |  | Causes powerful lightning to strike your opponent from above. |
| 410024001 | Thunder Cloud | ENEMY | ENEMY | 88 | 12 | 5 | 2500 |  | any | ALL |  |  |  |
| 410025001 | Resist Lightning | ENEMY | ALL | 32 | 1.5 | 3.5 | 1500 |  | ALL | ALL |  | Ice Storm | Increases your target's Lightning Resistance, but decreases their Fire and Ice Resistance. |
| 410026001 | Thunder Storm | POINT | ALL | 227 | 21 | 20 | 2500 |  | ALL | ALL |  |  | Strikes the area of effect with lightning. If the target is on horseback, they will be unable to move. |
| 410026002 | Thunder Storm | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Showers meteors on the designated area, possibly Stunning those in the area of effect. |
| 410026003 | Thunder Storm | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 410026004 | Thunder Storm | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 420001001 | Soul Bright | RADIATION | ENEMY | 14 | 1 | 7 | 0 |  | ALL | ALL |  | Mana Shield | Illuminates the area around you and removes the Hiding state from your enemies. |
| 420001002 | Soul Bright | RADIATION | ENEMY | 14 | 1 | 4 | 0 | 50 | Conjurer | ALL |  | Mana Shield | Illuminates the area around you and removes the Hiding state from your enemies. |
| 420001003 | Soul Bright | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Illuminates the area around you and removes the Hiding state from your enemies. |
| 420002001 | Mana Shield | TOGGLE | ALL | 24 | 3 | 10 | 0 |  | ALL | ALL |  | Clear Mind | Causes you to lose MP every time an enemy strikes, but reduces the amount of physical damage taken. |
| 420002002 | Mana Shield | TOGGLE | ALL | 24 | 3 | 10 | 0 | 50 | Conjurer | ALL |  | Clear Mind | Causes you to lose MP every time an enemy strikes, but reduces the amount of physical damage taken. |
| 420002003 | Magical Aid | MYSELF | ALL | 0 | 2.5 | 15 | 0 |  | any | ALL |  |  | Amplifies the effect of the next magic spell you use. |
| 420003001 | Sandstorm | ENEMY | ENEMY | 51 | 2 | 20 | 2500 |  | ALL | ALL |  | Psionic Blast | Raises a sand tornado from the ground that can cause the Sleep effect and damage your enemies. |
| 420004001 | Clear Mind | MYSELF | ALLY | 59 | 5 | 1.5 | 0 |  | ALL | ALL |  | Psychic Blade | Wraps your body in wind, making it harder for others to stop your casting. |
| 420004002 | Clear Mind | MYSELF | ALLY | 59 | 5 | 1.5 | 0 | 50 | Conjurer | ALL |  | Psychic Blade | Wraps your body in wind, making it harder for others to stop your casting. |
| 420005001 | Psychic Blade | ENEMY | ENEMY | 39 | 3.5 | 10 | 2500 |  | ALL | ALL |  | Blockade | Sends a psychic wave of energy at your target. The amount of damage inflicted is dependent on their Defense. |
| 420005002 | Psychic Blade | ENEMY | ENEMY | 39 | 3.5 | 10 | 2500 | 50 | Conjurer | ALL |  | Blockade | Sends a psychic wave of energy at your target. The amount of damage inflicted is dependent on their Defense. |
| 420005003 | Psychic Blade | BOLT | ENEMY | 0 | 0 | 0 | 2500 |  | Conjurer | ALL |  |  |  |
| 420005004 | Psychic Blade | BOLT | ENEMY | 0 | 0 | 0 | 2500 |  | Conjurer | ALL |  |  |  |
| 420006001 | Blockade | POINT | ALL | 79 | 5 | 120 | 300 |  | ALL | ALL |  | Summon Sandman | Creates an impermeable wall that no player can pass through. |
| 420006002 | Blockade | POINT | ALL | 79 | 5 | 20 | 300 | 50 | Conjurer | ALL |  | Summon Sandman | Creates an impermeable wall that no player can pass through. |
| 420007001 | Summon Sandman | POINT | ALL | 58 | 7 | 45 | 2500 |  | ALL | ALL |  | Malevolent Plant | Summons a giant tornado that inflicts damage and can put your opponent to Sleep. |
| 420007002 | Summon Sandman | SPHBOLT | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 420008001 | Supreme Mind | PASSIVE | ALL | 0 | 0 | 0 | 0 | 50 | Conjurer | ALL |  |  | Improves your skills by strengthening your mind. |
| 420009001 | Malevolent Plant | POINT | ALL | 192 | 2 | 60 | 300 |  | ALL | ALL |  |  | Summons a plant at the designated point. The plant will begin using ranged attacks on nearby enemies. |
| 430001001 | Blood Drain | ENEMY | ENEMY | 32 | 1 | 10 | 2500 |  | ALL | ALL |  | Mind Venom | Draws out your opponent's LP and makes it your own. |
| 430001002 | Blood Drain | ENEMY | ENEMY | 0 | 0 | 0 | 2500 |  | any | ALL |  |  | Draws out your opponent's LP and makes it your own. |
| 430001003 | Blood Drain | ENEMY | ENEMY | 32 | 1 | 10 | 2500 | 45 | Calamity | ALL |  | Mind Venom | Draws out your opponent's LP and makes it your own. |
| 430001004 | Blood Drain | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 430051001 | Gloom | MYSELF | ALL | 38 | 2 | 10 | 0 |  | ALL | ALL |  | Blood Drain | Places a Dark aura on a weapon, causing it to inflict Echo damage. |
| 430052001 | Infect | ENEMY | ENEMY | 12 | 2 | 5 | 2500 |  | ALL | ALL |  | Gloom | Injects venom into your opponent, inflicting the Poison effect upon them. |
| 430052002 | Infect | ENEMY | ENEMY | 12 | 2 | 5 | 2500 | 45 | Calamity | ALL |  | Gloom | Injects venom into your opponent, inflicting the Poison effect upon them. |
| 430052003 | Infect | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Injects venom into your opponent, inflicting the Poison effect upon them. |
| 430053001 | Mind Venom | ENEMY | ENEMY | 33 | 2.5 | 10 | 2500 |  | ALL | ALL |  | Dispel | Injects poison into your opponent via a small wound, inflicting the Addle effect on them. |
| 430053002 | Mind Venom | ENEMY | ENEMY | 0 | 2.5 | 10 | 2500 |  | any | ALL |  |  | Injects poison into your opponent via a small wound, inflicting the Addle effect on them. |
| 430053003 | Mind Venom | ENEMY | ENEMY | 33 | 2.5 | 10 | 2500 | 45 | Calamity | ALL |  | Dispel | Injects poison into your opponent via a small wound, inflicting the Addle effect on them. |
| 430053004 | Mind Venom | SPHERE | ENEMY | 0 | 0 | 10 | 0 |  | any | ALL |  |  | Injects poison into your opponent via a small wound, inflicting the Addle effect on them. |
| 430053005 | Mind Venom | ENEMY | ENEMY | 0 | 0 | 10 | 0 |  | any | ALL |  |  | Injects poison into your opponent via a small wound, inflicting the Addle effect on them. |
| 430054001 | Resist Malice | ENEMY | ALL | 32 | 1.5 | 3.5 | 1500 |  | ALL | ALL |  | Undermine | Increases your target's Poison and Dark Resistances, but reduces their Charm Resistance. |
| 430055001 | Dark Shield | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | Calamity | ALL |  | Conceal | Reduces the amount of Echo damage you take from Dark auras. |
| 430056001 | Pestilence | POINT | ENEMY | 62 | 5 | 6 | 2500 |  | ALL | ALL |  | Equalize | Summons forth a malign aura from the ground, causing Poison damage. Sometimes causes the Weaken effect. |
| 430056002 | Pestilence | SPHERE | ENEMY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  |  |
| 430057001 | Equalize | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  | Dark Frenzy | Grants a chance to dispel a positive status effect on your target when making a physical attack. |
| 430057002 | Equalize | ENEMY | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 430058001 | Dark Frenzy | MYSELF | ALL | 122 | 3 | 10 | 0 |  | ALL | ALL |  |  | Calls upon dark plumes that erupt from the ground, causing damage to surrounding enemies. |
| 430058002 | Dark Frenzy | RADIATION | ENEMY | 0 | 0 | 10 | 0 |  | ALL | ALL |  |  |  |
| 430058003 | Dark Frenzy | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 430059001 | Conceal | PARTY_ALL | ALLY | 240 | 3 | 120 | 1000 | 50 | Calamity | ALL |  |  | Grants the Hiding state to nearby party members. |
| 440001001 | Weakness | ENEMY | ENEMY | 18 | 1 | 5 | 2500 |  | ALL | ALL |  | Sandstorm | Decreases your target's Attack Power. |
| 440002001 | Dispel | ENEMY | ENEMY | 26 | 1 | 15 | 2500 |  | ALL | ALL |  | Resist Malice | Removes one of your target's positive status effects. |
| 440002002 | Dispel | ENEMY | ENEMY | 26 | 1 | 15 | 2500 | 45 | Calamity | ALL |  | Resist Malice | Removes one of your target's positive status effects. |
| 440002003 | Dispel | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 440003001 | Wasteland | POINT | ENEMY | 44 | 0.5 | 30 | 2500 |  | ALL | ALL |  | Siren Storm | Creates a poisonous swamp that restricts Movement Speed and Poisons your enemies. |
| 440003002 | Wasteland | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Creates a poisonous swamp that restricts Movement Speed and Poisons your enemies. |
| 440003003 | Wasteland | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Creates a poisonous swamp that restricts Movement Speed and Poisons your enemies. |
| 440004001 | Undermine | ENEMY | ENEMY | 23 | 0.5 | 10 | 2500 |  | ALL | ALL |  | Pestilence | Increases the amount of damage your target takes from the next successful attack. |
| 440004002 | Undermine | ENEMY | ENEMY | 23 | 0.5 | 10 | 2500 | 45 | Calamity | ALL |  | Pestilence | Increases the amount of damage your target takes from the next successful attack. |
| 440004003 | Undermine | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 440004004 | Undermine | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 440004005 | Undermine | ENEMY | ENEMY | 0 | 0 | 0 | 2500 |  | any | ALL |  |  |  |
| 440005001 | Psionic Blast | ENEMY | ENEMY | 25 | 1.5 | 5 | 2500 |  | ALL | ALL |  | Weaken | Directly damages your opponent's mind, reducing their MP. |
| 440005501 | Resist Charm | ENEMY | ALL | 32 | 1.5 | 3.5 | 1500 |  | ALL | ALL |  | Icy Strike | Increases your target's Charm Resistance, but reduces their Poison and Dark Resistance. |
| 440006001 | Stasis | ENEMY | ENEMY | 31 | 2 | 15 | 2500 | 45 | Jester | ALL |  | Leaden Hooves | Stops the duration of negative status effects and reduces the target's LP Recovery Rate. |
| 440006002 | Stasis | ENEMY | ENEMY | 31 | 2 | 15 | 2500 |  | Jester | ALL |  |  | Stops the duration of negative status effects and reduces the target's LP Recovery Rate. |
| 440007001 | Weaken | ENEMY | ENEMY | 18 | 1 | 5 | 2500 |  | ALL | ALL |  | Impede | Reduces your target's Defense. |
| 440007002 | Weaken | ENEMY | ENEMY | 0 | 1 | 5 | 2500 |  | ALL | ALL |  | Impede | Reduces your target's Defense. |
| 440008001 | Impede | ENEMY | ENEMY | 28 | 2 | 5 | 2500 |  | ALL | ALL |  | Resist Charm | Reduces your target's Dodge. |
| 440009001 | Siren Storm | POINT | ALL | 99 | 4.5 | 15 | 2000 |  | ALL | ALL |  | Cursed Bolt | Damages the MP of all enemies in the area of effect. It may also inflict Silence on them. |
| 440009002 | Siren Storm | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 440010001 | Leaden Hooves | ENEMY | ENEMY | 58 | 1 | 10 | 2500 | 50 | Jester | ALL |  |  | Reduces a horse's Trample capacity by sending its rider into a hallucinatory state. |
| 440011001 | Cursed Bolt | BOLT | ENEMY | 69 | 2 | 20 | 2500 |  | ALL | ALL |  |  | Fires a bolt at your target. Has a chance to inflict Curse and Disease on the target and any enemies surrounding them. |
| 440011002 | Cursed Bolt | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 500000000 | Movement Speed reduced | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Reduces your target's Movement Speed. |
| 500000001 | Sleep | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Puts your target to Sleep. |
| 500000002 | Stun | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Stuns your target. |
| 500000003 | Fatigue | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Inflicts your target with the Weaken effect. |
| 500000004 | Poison | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Inflicts your target with Poison. |
| 500000005 | Burn | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Inflicts your target with the Burn effect. |
| 500000006 | Insurance 50 | MYSELF | ALL | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Returns the 50% of EXP lost due to the Death Penalty. |
| 500000007 | Insurance 60 | MYSELF | ALL | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Returns the 60% of EXP lost due to the Death Penalty. |
| 500000008 | Insurance 70 | MYSELF | ALL | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Returns the 70% of EXP lost due to the Death Penalty. |
| 500000009 | Insurance 80 | MYSELF | ALL | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Returns the 80% of EXP lost due to the Death Penalty. |
| 500000010 | Insurance 90 | MYSELF | ALL | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Returns the 90% of EXP lost due to the Death Penalty. |
| 500000011 | Insurance 100 | MYSELF | ALL | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Returns the 100% of EXP lost due to the Death Penalty. |
| 500000012 | Ice | ENEMY | ALL | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Inflicts the Freeze effect on your target. |
| 500000013 | Attack | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Attack your target. |
| 500000014 | Attack MP | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Damages your target's MP |
| 500000015 | Tripped | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Inflicts the Trip effect on your target. |
| 500000016 | Practical Perfume | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Applies perfume that increases all of your abilities. |
| 500000017 | Virtuoso's Perfume 50 | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases Expertise gained by 50% |
| 500000018 | Virtuoso's Perfume 100 | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases Expertise gained by 100% |
| 500000019 | Virtuoso's Perfume 200 | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases Expertise gained by 100% |
| 500000020 | Burst Rod | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | A burst rod for a lucern hammer. |
| 500000021 | Burst Rod | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | A burst rod for a lucern hammer. |
| 500000022 | Casting Speed decreased | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Reduces the target's Casting Speed. |
| 500000023 | Charm | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Inflicts Confusion on your target. |
| 500000024 | Mochi | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases your Attack Power and Magical Attack Power. |
| 500000025 | Savage Cut | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases your Attack Power and Magical Attack Power. |
| 500000026 | Cupid's Arrow | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Prevents normal attacks from earning the ire of enemies. |
| 500000027 | Amulet of Enmity | ALLY | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Decreases your target's Attack Power. |
| 500000028 | Attack Power reduced | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Decreases your target's Attack Power. |
| 500000029 | Unseated | ENEMY | ENEMY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Inflicts the Unseat effect on your target. |
| 500000030 | Lapini Rice Cake | ALLY | ALLY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Turns the target into a lapin. |
| 500000031 | Cut Short | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Reduces the attacked target's maximum LP. |
| 500000032 | Attack MP 1 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 1 damage to your opponent's MP. |
| 500000033 | Attack MP 2 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 2 damage to your opponent's MP. |
| 500000034 | Attack MP 4 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 4 damage to your opponent's MP. |
| 500000035 | Attack MP 6 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 6 damage to your opponent's MP. |
| 500000036 | Attack MP 9 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 9 damage to your opponent's MP. |
| 500000037 | Attack MP 12 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 12 damage to your opponent's MP. |
| 500000038 | Attack MP 20 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 20 damage to your opponent's MP. |
| 500000039 | Attack MP 28 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 28 damage to your opponent's MP. |
| 500000040 | Attack MP 40 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 40 damage to your opponent's MP. |
| 500000041 | Attack MP 52 | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Does 52 damage to your opponent's MP. |
| 500000042 | Full Moon Belt | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Attack Power +7 Physical damage taken reduced by 4% |
| 500000043 | Victory Potion | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | While under its effect, PvP points gained are doubled. |
| 500000044 | Cloak for 15th Place | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 500000045 | Cloak for 5th Place | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 500000046 | Cloak for 1st Place | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 500000047 | MP Regen | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Restores the target's MP by invigorating their magical power. |
| 500000048 | Bleeding | ENEMY | ENEMY | 0 | 0 | 10 | 0 |  | any | 1H_SWORD, 2H_SWORD, LANCE, 1H_AXE, 1H_BLUNT, 1H_TRUMP, WAND |  |  | Inflict Bleed effect on opponent |
| 500000049 | DEF -5% | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Reduces your target's Defense. |
| 500000050 | DEF -10% | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Reduces your target's Defense. |
| 500000051 | DEF -15% | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Reduces your target's Defense. |
| 500000052 | DEF -25% | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Reduces your target's Defense. |
| 500000053 | DEF -50% | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Reduces your target's Defense. |
| 500000054 | Dwarven Candy | ALLY | ALLY | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Turns the target into a lapin. |
| 500000055 | Silence | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | BOW, CROSSBOW |  |  |  |
| 500000056 | Silence | ENEMY | ENEMY | 0 | 0 | 0 | 0 |  | any | BOW, CROSSBOW |  |  |  |
| 500000057 | Burn | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Put yourself under Burn effect |
| 500050000 | Non-Consumable Crafting Material Ticket | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Enables you to not consume your Crafting material |
| 500050001 | Crafting Expertise Gain Ticket | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases your Crafting Expertise |
| 500050002 | Silence | ENEMY | ENEMY | 0 | 0 | 0 | 4000 |  | any | BOW, CROSSBOW |  |  |  |
| 500050003 | Recipe Revolution | MYSELF | ALL | 0 | 0 | 0 | 2000 |  | any | ALL |  |  | Crafting Expertise will increase at a faster rate |
| 520000001 | Summon Mount | MYSELF | ALL | 22 | 3 | 180 | 0 |  | ALL | ALL |  | Horse Guardian | Allows you to summon your horse if you are in an area suitable for riding. |
| 520001001 | Jousting | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | Dragoon, Paladin | BareHAND, 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP, 2H_TRUMP, WAND, STAFF |  | Summon Mount | Allows you to use certain skills and charge attacks while on horseback. |
| 520002001 | Horse Archer | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | Predator | 1H_SWORD, BOW, CROSSBOW |  | Summon Mount | Allows you to use certain skills and charge attacks while on horseback. |
| 520003001 | Median Riding | PASSIVE | ALL | 0 | 0 | 0 | 0 | 45 | Calamity | 1H_SWORD, WAND, STAFF |  | Summon Mount | Allows you to use certain skills and charge attacks while on horseback. |
| 520004001 | Horse Guardian | TOGGLE | ALL | 5 | 0 | 0 | 0 |  | ALL | ALL | ✓ | Equine Advantage | While under this effect, you absorb all damage meant to be taken by your horse. Toggle on/off for effect. |
| 520005001 | Equine Advantage | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Increases ranged attack distance while on horseback. Also, range is increased when using a one-handed sword on horseback. |
| 520005002 | Equine Advantage | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  |  |
| 520005003 | Equine Advantage | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | 1H_SWORD |  |  |  |
| 530000000 | Unjo | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the effectiveness of potions. |
| 530000001 | Belcana | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Unifies your spirit and increases your MP Recovery Rate. |
| 530000002 | Nausyz | MYSELF | ALL | 0 | 0 | 3 | 0 |  | any | ALL |  |  | Enables you to camouflage your appearance where you stand. |
| 530000003 | Osila | MYSELF | ALL | 0 | 0 | 1.5 | 0 | 0 | any | ALL |  |  | Increases the Attack Speed of your target. |
| 600000001 | Reveille Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP +2% |
| 600000002 | Reveille Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP +4% |
| 600000003 | Reveille Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP +6% |
| 600000004 | Reveille Lv4 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP +9% |
| 600000005 | Reveille Lv5 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP +12% |
| 600000006 | Reveille Lv6 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP +15% |
| 600000011 | Meditation Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP +2% |
| 600000012 | Meditation Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP +4% |
| 600000013 | Meditation Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP +6% |
| 600000014 | Meditation Lv4 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP +9% |
| 600000015 | Meditation Lv5 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP +12% |
| 600000016 | Meditation Lv6 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP +15% |
| 600000021 | Healing Chant Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP Recovery Rate +5% |
| 600000022 | Healing Chant Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP Recovery Rate +8% |
| 600000023 | Healing Chant Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP Recovery Rate +11% |
| 600000024 | Healing Chant Lv4 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP Recovery Rate +15% |
| 600000031 | Calming Chant Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP Recovery Rate +5% |
| 600000032 | Calming Chant Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP Recovery Rate +8% |
| 600000033 | Calming Chant Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP Recovery Rate +11% |
| 600000034 | Calming Chant Lv4 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | MP Recovery Rate +15% |
| 600000041 | Call to Arms LV1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Maximum number of guild members allowed +2. |
| 600000042 | Call to Arms LV2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Maximum number of guild members allowed +4. |
| 600000043 | Call to Arms LV3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Maximum number of guild members allowed +6. |
| 600000044 | Call to Arms LV4 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Maximum number of guild members allowed +8. |
| 600000045 | Call to Arms LV5 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Maximum number of guild members allowed +10. |
| 600000046 | Call to Arms LV6 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Maximum number of guild members allowed +13. |
| 600000047 | Call to Arms LV7 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Maximum number of guild members allowed +16. |
| 600000051 | Guild Prestige Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of honor gained when defeating a player increased by 1%. |
| 600000052 | Guild Prestige Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of honor gained when defeating a player increased by 2%. |
| 600000053 | Guild Prestige Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of honor gained when defeating a player increased by 3%. |
| 600000054 | Guild Prestige Lv4 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of honor gained when defeating a player increased by 4%. |
| 600000055 | Guild Prestige Lv5 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of honor gained when defeating a player increased by 6%. |
| 600000056 | Guild Prestige Lv6 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of honor gained when defeating a player increased by 8%. |
| 600000057 | Guild Prestige Lv7 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of honor gained when defeating a player increased by 10%. |
| 600000061 | Experience Boost Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of experience points gained when defeating a monster +2%. |
| 600000062 | Experience Boost Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of experience points gained when defeating a monster +3%. |
| 600000063 | Experience Boost Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of experience points gained when defeating a monster +4%. |
| 600000064 | Experience Boost Lv4 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of experience points gained when defeating a monster +5%. |
| 600000065 | Experience Boost Lv5 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of experience points gained when defeating a monster +6%. |
| 600000066 | Experience Boost Lv6 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of experience points gained when defeating a monster +7%. |
| 600000067 | Experience Boost Lv7 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of experience points gained when defeating a monster +8%. |
| 600000068 | Experience Boost Lv8 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Amount of experience points gained when defeating a monster +10%. |
| 600000071 | Guild Courage Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Physical damage taken is reduced by 3%. |
| 600000072 | Guild Courage Lv 2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Physical damage taken is reduced by 6%. |
| 600000073 | Guild Courage Lv 3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Physical damage taken is reduced by 10%. |
| 600000081 | Guild Resistance Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Magical damage taken is reduced by 3%. |
| 600000082 | Guild Resistance Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Magical damage taken is reduced by 6%. |
| 600000083 | Guild Resistance Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Magical damage taken is reduced by 10%. |
| 600000201 | Glory of War Lv1 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 18%. Consumes one White Crystal. |
| 600000202 | Glory of War Lv2 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 36%. Consumes one White Crystal. |
| 600000203 | Glory of War Lv3 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 54%. Consumes one White Crystal. |
| 600000204 | Glory of War Lv4 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 72%. Consumes one White Crystal. |
| 600000205 | Glory of War Lv5 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 90%. Consumes one White Crystal. |
| 600000211 | Adrenaline Rush Lv1 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 10%. This consumes one Yellow Crystal. |
| 600000212 | Adrenaline Rush Lv2 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 20%. This consumes one Yellow Crystal. |
| 600000213 | Adrenaline Rush Lv3 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 30%. This consumes one Yellow Crystal. |
| 600000214 | Adrenaline Rush Lv4 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 40%. This consumes one Yellow Crystal. |
| 600000215 | Adrenaline Rush Lv5 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 50%. This consumes one Yellow Crystal. |
| 600000221 | Battle Frenzy Lv1 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, all attributes increase by 1. This consumes one Silver Crystal. |
| 600000222 | Battle Frenzy Lv2 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, all attributes increase by 2. This consumes one Silver Crystal. |
| 600000223 | Battle Frenzy Lv3 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, all attributes  increase by 3. This consumes one Silver Crystal. |
| 600000224 | Battle Frenzy Lv4 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, all attributes increase by 4. This consumes one Silver Crystal. |
| 600000225 | Battle Frenzy Lv5 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, all attributes increase by 5. This consumes one Silver Crystal. |
| 600000231 | Battle Cry Lv1 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, Attack Power and Magical Attack Power increase by 2%. This consumes one Dark Crystal. |
| 600000232 | Battle Cry Lv2 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, Attack and Power Magical Attack Power increase by 4%. This consumes one Dark Crystal. |
| 600000233 | Battle Cry Lv3 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, Attack Power and Magical Attack Power increase by 6%. This consumes one Dark Crystal. |
| 600000234 | Battle Cry Lv4 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, Attack Power and Magical Attack Power increase by 8%. This consumes one Dark Crystal. |
| 600000235 | Battle Cry Lv5 | MYSELF | ALLY | 0 | 0 | 60 | 0 |  | any | ALL |  |  | While under this effect, Attack Power and Magical Attack Power increased by 10%. This consumes one Dark Crystal. |
| 610000201 | Glory of War Lv1 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 18%. Consumes one White Crystal. |
| 610000202 | Glory of War Lv2 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 36%. Consumes one White Crystal. |
| 610000203 | Glory of War Lv3 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 54%. Consumes one White Crystal. |
| 610000204 | Glory of War Lv4 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 72%. Consumes one White Crystal. |
| 610000205 | Glory of War Lv5 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While active, honor gained when an enemy player is defeated increases by 90%. Consumes one White Crystal. |
| 610000211 | Adrenaline Rush Lv1 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 10%. This consumes one Yellow Crystal. |
| 610000212 | Adrenaline Rush Lv2 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 20%. This consumes one Yellow Crystal. |
| 610000213 | Adrenaline Rush Lv3 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 30%. This consumes one Yellow Crystal. |
| 610000214 | Adrenaline Rush Lv4 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 40%. This consumes one Yellow Crystal. |
| 610000215 | Adrenaline Rush Lv5 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, LP and MP Recovery Rates increase by 50%. This consumes one Yellow Crystal. |
| 610000221 | Battle Frenzy Lv1 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, all attributes increase by 1. This consumes one Silver Crystal. |
| 610000222 | Battle Frenzy Lv2 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, all attributes increase by 2. This consumes one Silver Crystal. |
| 610000223 | Battle Frenzy Lv3 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, all attributes  increase by 3. This consumes one Silver Crystal. |
| 610000224 | Battle Frenzy Lv4 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, all attributes increase by 4. This consumes one Silver Crystal. |
| 610000225 | Battle Frenzy Lv5 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, all attributes increase by 5. This consumes one Silver Crystal. |
| 610000231 | Battle Cry Lv1 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, Attack Power and Magical Attack Power increase by 2%. This consumes one Dark Crystal. |
| 610000232 | Battle Cry Lv2 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, Attack and Power Magical Attack Power increase by 4%. This consumes one Dark Crystal. |
| 610000233 | Battle Cry Lv3 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, Attack Power and Magical Attack Power increase by 6%. This consumes one Dark Crystal. |
| 610000234 | Battle Cry Lv4 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, Attack Power and Magical Attack Power increase by 8%. This consumes one Dark Crystal. |
| 610000235 | Battle Cry Lv5 | CLAN | ALLY | 0 | 0 | 0 | 1500 |  | any | ALL |  |  | While under this effect, Attack Power and Magical Attack Power increased by 10%. This consumes one Dark Crystal. |
| 620000001 | Dismantle Siege Weapon | ENEMY | ALL | 0 | 0 | 0 | 1000 |  | any | ALL |  |  | Dismantles a built siege weapon. |
| 620000011 | Siege-Weapon Research Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the chance of success when building a siege weapon by 10%. |
| 620000012 | Siege-Weapon Research Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the chance of success when building a siege weapon by 20%. |
| 620000013 | Siege-Weapon Research Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the chance of success when building a siege weapon by 40%. |
| 620000021 | Siege-Weapon Construction Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Decreases the time needed to build a siege weapon by 10%. |
| 620000022 | Siege-Weapon Construction Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Decreases the time needed to build a siege weapon by 30%. |
| 620000023 | Siege-Weapon Construction Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Decreases the time needed to build a siege weapon by 50%. |
| 620000031 | Siege-Weapon Enhancement Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the siege weapon's maximum LP by 10%. |
| 620000032 | Siege-Weapon Enhancement Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the siege weapon's maximum LP by 30%. |
| 620000033 | Siege-Weapon Enhancement Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the siege weapon's maximum LP by 50%. |
| 620000041 | Siege-Weapon Training Lv1 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the number of siege weapons that can be placed in the same area by 1. |
| 620000042 | Siege-Weapon Training Lv2 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the number of siege weapons that can be placed in the same area by 2. |
| 620000043 | Siege-Weapon Training Lv3 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the number of siege weapons that can be placed in the same area by 3. |
| 620001011 | Battering-Ram Construction | MYSELF | ALL | 0 | 30 | 15 | 0 |  | ALL | ALL |  |  | Use components at a siege-weapon construction site to build a battering ram. |
| 620001021 | Belfry Construction | MYSELF | ALL | 0 | 45 | 15 | 0 |  | ALL | ALL |  |  | Use components at a siege-weapon construction site to build a belfry. |
| 620001031 | Catapult Construction | MYSELF | ALL | 0 | 45 | 15 | 0 |  | ALL | ALL |  |  | Use components at a siege-weapon construction site to build a catapult. |
| 620001041 | Ballista Construction | ALLY | ALL | 0 | 30 | 15 | 1000 |  | ALL | ALL |  |  | Use components to repair a damaged ballista. |
| 620001051 | Trebuchet Repair | ALLY | ALL | 0 | 45 | 15 | 1000 |  | ALL | ALL |  |  | Use components to repair a damaged trebuchet. |
| 620001061 | Cheval de Frise Installation | POINT | ALL | 0 | 15 | 15 | 1000 |  | ALL | ALL |  |  | Use components to build a cheval de frise. |
| 620002011 | Battering Ram | MYSELF | ALL | 0 | 0 | 15 | 0 |  | ALL | ALL |  |  | Use battering ram. |
| 620002012 | Battering Ram | ENEMY | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Use battering ram. |
| 620002013 | Battering Ram | BREATH | ENEMY | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Use battering ram. |
| 620002021 | Deploy | MYSELF | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Deploy belfry. |
| 620002031 | Launch | MYSELF | ALL | 0 | 0 | 11 | 0 |  | ALL | ALL |  |  | Launch projectile. |
| 620002032 | Launch | GBOLT | ENEMY | 0 | 0 | 0 | 15000 |  | ALL | ALL |  |  | Launch projectile. |
| 620002033 | Launch | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Launch projectile. |
| 620002041 | Launch | MYSELF | ALL | 0 | 0 | 11 | 0 |  | ALL | ALL |  |  | Launch projectile. |
| 620002042 | Launch | GBOLT | ENEMY | 0 | 0 | 0 | 15000 |  | ALL | ALL |  |  | Launch projectile. |
| 620002043 | Launch | SPHERE | ENEMY | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Launch projectile. |
| 620002051 | Ballista | POINT | ALL | 0 | 0 | 2.5 | 0 |  | ALL | ALL |  |  | Fire ballista. |
| 620002052 | Ballista | BOLT | ENEMY | 0 | 0 | 0 | 5000 |  | ALL | ALL |  |  | Fire ballista. |
| 620002061 | Cheval de Frise | BREATH | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | You take damage if you touch this while on horseback. |
| 620002062 | Cheval de Frise | ENEMY | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | You take damage if you touch this while on horseback. |
| 700000001 | Woodlands | RADIATION | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Reduces Movement Speed when mounted on a horse by 50% |
| 700000002 | Woodlands | TOGGLE | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | Reduces Movement Speed when mounted on a horse by 50% |
| 700000011 | Siege-Weapon Construction Zone | RADIATION | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | You are able to use your siege-weapon construction skills here. |
| 700000012 | Siege-Weapon Construction Zone | TOGGLE | ALL | 0 | 0 | 0 | 0 |  | ALL | ALL |  |  | You are able to use your siege-weapon construction skills here. |
| 900010001 | Fighting Spirit | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | 1H_SWORD, LANCE, 1H_AXE, 1H_BLUNT, 1H_TRUMP, WAND |  |  | Your matchless dexterity and unparalleled fighting spirit give you a mastery of one-handed weapons. |
| 900010002 | Adaptability | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your superb adaptability lessens the time you suffer Ailments. |
| 900010003 | Pharmaceutics | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your vast knowledge of herbs and alchemical formulae allows you to increase the effectiveness of your elixirs. |
| 900020001 | Nature's Harmony | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your MP costs are reduced thanks to your abundant knowledge and skilled use of magic. |
| 900020002 | Eagle Eye | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | BOW, CROSSBOW |  |  | Your incomparable eyesight and skill with the bow allows you to attack from further away. |
| 900020003 | Steadfastness | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your calm elven heart gives you a strong resistance against Charm spells. |
| 900030001 | Stronghearted | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your inborn dwarven determination allows you to stand strong in the face of adversity, letting you survive a killing blow. |
| 900030002 | Dwarf Spirit | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT |  |  | Your dwarven strength makes you an expert at using axes and blunt weapons. |
| 900030003 | Filial Piety | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your strong sense of loyalty allows you to sacrifice yourself for an ally. |
| 900040001 | Acute Senses | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your acute senses give you the ability to critically hit like a skilled myrine hunter. |
| 900040002 | Calmness | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your calmness gives you the ability to recover MP by converting damage into spiritual power. |
| 900040003 | Sharpness | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your sharp senses give you the ability to evade more easily. |
| 900050001 | Stone Skin | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your thick enkidu skin offers a rock-hard layer of protection. |
| 900050002 | Strong Arm | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | BareHAND, 2H_SWORD, POLE_ARM, 2H_AXE, 2H_BLUNT, 2H_TRUMP, BOW, CROSSBOW, STAFF |  |  | Your strong arms give you the ability to utilize strength when fighting bare-handed or with heavy weapons. |
| 900050003 | Lapin Support | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Lapins receive less damage from physical attacks when they're in your party. |
| 900060001 | Magic Resistance | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your proficiency in magic gives you the special ability to resist magical attacks. |
| 900060002 | Inner Light | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Your adeptness with magic gives you the ability to recover your MP at a faster rate. |
| 900060003 | Enkidu Support | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Enkidus receive less damage from magical attacks when they're in your party. |
| 910110001 | Empower | PASSIVE | ALL | 0 | 0 | 0 | 0 | 20 | Gladiator, Juggernaut, Dragoon | ALL |  |  | Increases the damage done by your weapons in melee combat. |
| 910120001 | Guard | PASSIVE | ALL | 0 | 0 | 0 | 0 | 20 | Knight, General, Paladin | ALL |  |  | Reduces the damage of incoming attacks through guarding in a defensive stance. |
| 920110001 | Hawkeye | PASSIVE | ALL | 0 | 0 | 0 | 0 | 20 | Archer, Vigilance, Predator | ALL |  | Accelerate | Grants you the power to survey the area with the watchful eye of a hawk, increasing your Accuracy. |
| 920120001 | Shifty | PASSIVE | ALL | 0 | 0 | 0 | 0 | 20 | Agent, Assassin, Disturbance | ALL |  |  | Increases your Dodge by causing you to focus on swift movements. |
| 930110001 | Inspiration | PASSIVE | ALL | 0 | 0 | 0 | 0 | 20 | Priest, Cleric, Enchanter | ALL |  | Divine Aid | Increases your Spirit through honed senses. |
| 930120001 | Blessed Garments | PASSIVE | ALL | 0 | 0 | 0 | 0 | 20 | Ascetic, Monk, Exorcist | ALL |  |  | When you wear equipment that has a Light aura, you gain Resistance to Poison, Charm, and Magic. |
| 940110001 | Scholar | PASSIVE | ALL | 0 | 0 | 0 | 0 | 20 | Wizard, Warlock, Conjurer | ALL |  |  | Your vast knowledge of the magical arts increases your magical strength. |
| 940120001 | Shadow Garments | PASSIVE | ALL | 0 | 0 | 0 | 0 | 20 | Darklore, Jester, Calamity | ALL |  |  | When you wear equipment that has a Dark aura, you gain Resistance to Fire, Ice, and Lightning. |
| 950000001 | Self-Actualization | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | All Attributes +1. |
| 950000002 | Heart of Gold | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | LP Recovery Skills become more effective. |
| 950000003 | Tome of the Inferno | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Fire Resistance, Burn Resistance, Fire Elemental Damage and Attack Power all increase, but Ice Resistance decreases. |
| 950000004 | Tome of the Blizzard | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Ice Resistance, Freeze Resistance, Ice Elemental Damage and Spell Interrupt Resistance all increase, but Lightning Resistance decreases. |
| 950000005 | Tome of the Fulmination | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Lightning Resistance, Trip Resistance, Lightning Elemental Damage, and Accuracy all increase, but Fire Resistance decreases. |
| 950000006 | Rage | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases damage when you hit with a physical attack. |
| 950000007 | Smooth Ride | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Reduces penalties incurred while on horseback. |
| 950000008 | Guardian's Secret | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Reduces both the chances of and damage taken from a Critical Hit. |
| 950000009 | Tome of Endless Night | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Dark Resistance, Charm Resistance, and Disorder Resistance all increase, but Light Resistance decreases. |
| 950000010 | Tome of Eternal Light | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Light Resistance, Magic Resistance, and Ailment Resistance all increase, but Dark Resistance decreases. |
| 950000011 | Survivalist | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases Defense and the effectiveness of potions. |
| 950000012 | Acrobatics | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Grants a chance to evade physical ranged attacks and increases Dodge, but decreases Accuracy. |
| 950000013 | Sword Lore | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Damage and Accuracy increase when you attack from the front, but your Dodge decreases. |
| 999999991 | test001 | PASSIVE | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  | Lunge | Increases the effectiveness of potions. |
| 999999992 | Test 01 | MYSELF | ALL | 15 | 2 | 10 | 0 |  | any | ALL |  | Serum | Consumes a Venom to coat your weapons. |
| 999999993 | Test 02 | MYSELF | ALL | 15 | 2 | 10 | 0 |  | any | ALL |  | Serum | Consumes a Venom to coat your weapons. |
| 999999994 | Test 03 | MYSELF | ALL | 15 | 2 | 10 | 0 |  | any | ALL |  | Serum | Consumes a Venom to coat your weapons. |
| 999999995 | Test 04 | MYSELF | ALL | 15 | 2 | 10 | 0 |  | any | ALL |  | Serum | Consumes a Venom to coat your weapons. |
| 999999996 | Test 05 | MYSELF | ALL | 15 | 2 | 10 | 0 |  | any | ALL |  | Serum | Consumes a Venom to coat your weapons. |
| 999999997 | Test 06 | MYSELF | ALL | 15 | 2 | 10 | 0 |  | any | ALL |  | Serum | Consumes a Venom to coat your weapons. |
| 999999998 | Hyper Speed | TOGGLE | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Grants you a blessing that increases Movement Speed by an incredible amount. |
| 999999999 | Boost Speed | TOGGLE | ALLY | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Grants you a blessing that increases Movement Speed. |
| 1000000000 | Non-Consumable Crafting Material Ticket | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Enables you to not consume your Crafting material |
| 1000000001 | Crafting Expertise Gain Ticket | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases your Crafting Expertise |
| 1000000002 | Unjo | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Increases the effectiveness of potions. |
| 1000000003 | Belcana | MYSELF | ALL | 0 | 0 | 0 | 0 |  | any | ALL |  |  | Unifies your spirit and increases your MP Recovery Rate. |
| 1000000004 | Nausyz | MYSELF | ALL | 0 | 0 | 3 | 0 |  | any | ALL |  |  | Enables you to camouflage your appearance where you stand. |
| 1000000005 | Osila | MYSELF | ALL | 0 | 0 | 1.5 | 0 | 0 | any | ALL |  |  | Increases the Attack Speed of your target. |
