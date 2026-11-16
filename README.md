# Book of Dogs

A World of Warcraft: Forever addon for guilds to keep a shared book of notable players from outside the guild, ranked by votes.

## Features
- Right-click any player → **Add to Book of Dogs** with a short note
- Up/down votes (one per BattleTag account: all your characters share one vote; only a salted hash of your BattleTag is shared, never the tag), ranked list, search, right-click an entry to see who voted
- Syncs with members of the same guild (each guild keeps its own book)
- Guildmates can't be added. The addon checks descriptions locally and rejects blocked terms in received entries.
- The guild master manages editors. Officers and appointed editors can edit and delete entries.
- Dog icon above the nameplate of anyone in the Book, even when not targeted (on party/raid frames inside dungeons and raids, where nameplates are locked)
- Tags (Toxic, Ninja, Scammer, Griefer, Dumbass, KOS) shown as pills under each note; search by tag name
- Heads-up alerts when someone in the Book joins your group, invites you, whispers you, or trades with you
- Minimap button (drag to move), `/dogs` to open

## Install
Copy the `BookOfDogs` folder into `World of Warcraft\_forever_\Interface\AddOns\` and fully restart WoW.

## Commands
`/dogs` open · `/dogs add` add target · `/dogs sync` pull the whole book · `/dogs rebuild` reset your copy from the guild · `/dogs status` sync info · `/dogs minimap` show/hide the button · `/dogs icons` show/hide nameplate icons · `/dogs frames` show/hide the party/raid frame icons · `/dogs chat` show/hide chat icons · `/dogs alerts` turn heads-up alerts on/off · `/dogs plates` turn on nameplates for all nearby players · `/dogs icon <size> <height>` adjust the icon

Created by CHogan. Main contributors: Oasli, Relreo.
