# Book of Dogs

A World of Warcraft: Forever addon for guilds to keep a shared book of notable players from outside the guild, ranked by votes.

## Features
- Right-click any player → **Add to Book of Dogs** with a short note
- Up/down votes (one per BattleTag account: all your characters share one vote; only a salted hash of your BattleTag is shared, never the tag), ranked list, search, right-click an entry to see who voted
- Syncs with members of the same guild on the same feed
- Guildmates can't be added. The addon checks descriptions locally and rejects blocked terms in received entries.
- The guild master manages editors. Officers and appointed editors can edit and delete entries.
- Dog icon above the nameplate of anyone in the Book, even when not targeted
- Minimap button (drag to move), `/dogs` to open

## Install
Copy the `BookOfDogs` folder into `World of Warcraft\_forever_\Interface\AddOns\` and fully restart WoW.

## Feeds

Every guild starts on its own `default` feed. Open the Book with `/dogs`, click the **Feed** button beside Search, and choose a saved feed or **Join a feed…** to enter a GUID shared by your guildmates. Seeds are case-insensitive and accept up to 64 letters, numbers, and hyphens. You can also use `/dogs feed <guid>` to switch, `/dogs feed` to see your current selection, or `/dogs feed default` to switch back. Each feed keeps its own entries, votes, and editor list.

Use **Rename current feed…** to give a feed a local label. The picker shows the label and the seed, and the label is saved on your client. Clear the label to restore the original display name.

The original Dog default feed keeps its existing book, admin, older-client sync, and guild-chat announcements. Other feeds require this version and sync through addon messages. A seed selects a feed within WoW's guild channel. Guild members with a modified client can read or send addon messages, so the seed provides no secrecy or authentication.

## Commands
`/dogs` open · `/dogs add` add target · `/dogs sync` pull the whole book · `/dogs rebuild` reset your copy from the guild · `/dogs status` sync info · `/dogs minimap` show/hide the button · `/dogs icons` show/hide nameplate icons · `/dogs plates` turn on nameplates for all nearby players · `/dogs icon <size> <height>` adjust the icon

Created by CHogan.
