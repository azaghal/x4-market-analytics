Market Analytics
================


About
-----

*Market Analytics* provides a tabular overview menu of station trade offers with filtering, sorting, and interaction capabilities (in-game spreadsheet).


Features
--------

-   Compact spreadsheet-like interface for listing (known) trade offers from (known) stations. Displays faction, station, sector, distance (to reference sector), ware, offer type (buys/sells), price, markup, and amount for each listed trade offer.
-   Comprehensive filtering capabilities. Sector, ware, and volume filters are kept in sync with the map filters.
-   Customizable multi-column sorting.
-   Direct interaction with stations and station offers via right-click interaction menu.
-   Accessible directly from/on the map menu.


Usage
-----

*Market Analytics* can be opened via right-panel button in the map view. The menu employs combination of left and right mouse clicks to make certain operations convenient and faster. It is highly recommended to get familiarised with the interface by clicking on the question mark shown on the right side just above the *Refresh* button (not to be confused with the map menu's own question mark button).

Quick recap:

-   Trade offers are cached for performance reasons.
-   Reference sector for measuring distances is shown in the upper-left corner.
-   Reset button resets the filters, refresh button updates the trade offers.
-   Use left-click and right-click on column labels to set sorting order and sorting order priorities.
-   Filter controls are shown under the column names. Left-click to set the filter, right-click to clear the filter. Dropdowns do not support clearing via right-click.
-   Left-click on trade offer's faction icon, sector name, or ware name to set the filter value.
-   Right-click on trade offer's faction icon, sector name, or ware name to *exclude* the value from the filter.
-   Distance is measured in *system* jumps. For example, both *Hatikvah's Choice I* and *Hatikvah's Choice III* are considered to be just one jump away from Argon Prime.
-   Faction filter supports using trade rules from global orders as filter (*Group By* feature).


Requirements
------------

-   Game version 8.00.HF4 (no DLCs required). Game version 9.00 is explicitly **not** supported at time of this writing.
-   [UI Extensions and HUD](https://www.nexusmods.com/x4foundations/mods/552)


Compatibility
-------------

Despite the best efforts to keep the mod as unintrusive as possible, some features have required plugging into the vanilla code beyond what is provied by the *UI Extensions and HUD* mod. While done in the least disrupting way possible, this mod may not be compatible with any other mods (beyond *UI Extensions and HUD* itself) that:

-   Fully replace the `MapMenu` functions: `menu.setSectorFilter`, `menu.filterTradeWares`, `menu.filterTradeVolume`, `menu.filterTradeRelation`, `menu.closeContextMenu`.
-   Fully replace the `InteractMenu` functions: `menu.onCloseElement`.

*Market Analytics* does **not** replace these functions, but it does monkey-patch them to insert some extra mod-related logic.

Compatibility with other mods is not guaranteed, but at the time of this writing there are no known compatibility issues with other mods.


Known issues
------------

Majority (if not all) of the listed limitations related to the vanilla widget system are resolvable, but would require changes to the core widget system itself which would be a better fit for some kind of "core" mod (like *UI Extensions and HUD*).

-   Mod menu is (probalby) not controller-friendly.
-   Although unlikely, the mod menu *may* crash the UI. A singular case where this happened reliably has been fixed with a workaround, but it could happen the workaround is insufficient.
-   Some buttons may fail to render due to vanilla limitation on how many buttons can be shown at the same time (200). The mod does employ some workarounds to deal with this while preserving all the features, but the solution is not foolproof. This is a limitation of the vanilla widget system.
-   Global help overlay may fail to render all of the mod menu's help overlay elements due to limitation on how many help overlay elements can be shown at the same time (25). This is a limitation of the vanilla widget system.
-   Custom help button cannot toggle off help overlay if the overlay was initially toggled on by the main help overlay button. This is a limitation of the vanilla widget system.
-   Custom help button may get out of sync with help overlay state. Clicking the button multiple times should bring it back into sync. This is a limitation of the vanilla widget system.
-   Dropdown filters cannot be cleared via right-click.


Roadmap
-------

-   Explicit filter control for showing/hiding enemy trade offers.
-   Trade offer pinning (that also ignores filters).
-   Trade offer station pinning (that also ignores filters).
-   Filtering by ware groups.
-   Customizable filter (reset) defaults.
-   Auto-refresh offers when queing up a trade.
-   Filtering by minimum distance (maybe).
-   Amount as multiple of selected ship capacity (maybe).
-   Tooltips with faction list for faction group filters.


Credits
-------

Creation of this mod has been hugely insipired by [Trade Ledger](https://www.nexusmods.com/x4foundations/mods/1962), a mod created by [Necoval](https://www.nexusmods.com/profile/Necoval). Big shout-out to the author for developing and making *Trade Ledger* mod available for everyone to learn from and use in their playthroughs.


License
-------

All code, documentation, and assets implemented as part of this mod are released under the terms of MIT license (see the accompanying `LICENSE` file), with the following exceptions.
