-- $Id: Cartographer_Sidelist.lua 65877 2008-03-25 23:44:59Z sekuyo $

-- Set up key bindings
BINDING_HEADER_CARTOGRAPHER_SIDELIST = "Cartographer Sidelist"
BINDING_NAME_CARTOGRAPHER_SIDELIST_TOGGLE = "Turn Sidelist on/off" 

local L = AceLibrary("AceLocale-2.2"):new("Sidelist")
local Tablet = AceLibrary("Tablet-2.0")

-- Table of registered Cartographer_Notes icons
local iconList = nil

-- Track session state of sidelist
local sidelistIsOpen

-- Session cache of open/closed states for categories.  Default is closed.
--      category name => bool
local categoryOpen = { }

Cartographer_Sidelist = Cartographer:NewModule("Sidelist",
            "AceEvent-2.0",
            "AceConsole-2.0",
            "AceHook-2.1",
            "AceDebug-2.0")

Cartographer_Sidelist:SetDebugLevel(2)

-- Session throb state.
Cartographer_Sidelist.throbData = { }


-- Return the list of keys in table t
local
function keys(t)
    local ret = { }

    for k, _ in pairs(t)
    do
        table.insert(ret, k)
    end

    return ret
end     -- keys


local
function multiplyCoords(x, y)
    return x * 100, y * 100
end     -- multiplyCoords


-- Function that returns an iterator to traverse an ordered table.
-- t:  input table
-- comparator:  function called to define the ordering between two elements
--              of t.  Should return true if first argument should be
--              ordered before second argument.  Each argument is a table of
--              the form whose 'k' key contains the key from t, and 'v' key
--              contains the value t[k].
-- iterFunc:  usually ipairs (if t is a list or you want 1-based array
--            output), or pairs (if t is a table of key-value pairs and you
--            want key-value pair output).
local
function orderedIter(t, comparator, iterFunc)
    local keyValueBundles = { }

    -- Create array of t's keys bundled with their values.  This lets us
    -- defer handling of identical keys and/or values to the comparator
    -- function, since it will have access to both.
    for k, v in iterFunc(t)
    do
        local bundle = { }
        bundle.k = k
        bundle.v = v
        table.insert(keyValueBundles, bundle)
    end

    -- Order the values using the comparator function.
    table.sort(keyValueBundles, comparator)

    -- Return an iterator that traverses the ordered bundles.
    local i = 0
    local n = #keyValueBundles
    return function()
        i = i + 1
        if i <= n
        then
            return iterFunc == ipairs and i or keyValueBundles[i].k,
                        keyValueBundles[i].v
        end
    end
end     -- orderedIter


-- Return number of keys in t.
local
function numberOfKeys(t)
    return not t and 0 or #keys(t)
end     -- numberOfKeys


-- Return a list containing the stable order of unique elements in the given
-- list.
--[[
local
function uniq(l)
    local ret = { }

    for _, v in ipairs(l)
    do
        ret[v] = true
    end

    return keys(ret)
end     -- uniq
]]


-- Return list containing names of Cartographer Notes' external databases.
local
function getExternalDatabaseNames(zone)
    return keys(Cartographer_Notes.externalDBs)
end     -- getExternalDatabaseNames


-- Return reference to the table containing notes in the given zone for the
-- given dbName.
-- If dbName is nil, the internal note table is used.
local
function getNoteTable(zone, dbName)
    return rawget(dbName and Cartographer_Notes.externalDBs[dbName] or
                    Cartographer_Notes.db.account.pois, zone)
end     -- getNoteTable


-- Mapping of special-case dbName's to info needed to get the icon's
-- path for the given note.  An entry in this mapping implies note does
-- not have the usual icon field or it needs to be overridden.
local dbName2noteIconPathOverrideFn = {
    Mailboxes = function(note)
            return "Interface\\Addons\\Cartographer_Mailboxes\\Artwork\\Mail"
        end,
    -- For Herbalism, Mining and Fishing, the localized text is stored
    -- for the note's title.  We need to use Babble lib to get the
    -- reverse translation, since that's how the icons are registered
    -- with Cartographer_Notes.
    Herbalism = function(note)
            local key =
                AceLibrary("Babble-Herbs-2.2"):GetReverseTranslation(note)
            return iconList[key].path
        end,
    Mining = function(note)
            local key =
                AceLibrary("Babble-Ore-2.2"):GetReverseTranslation(note)
            return iconList[key].path
        end,
    Fishing = function(note)
            local key =
                AceLibrary("Babble-Fish-2.2"):GetReverseTranslation(note)
            return iconList[key].path
        end,
}

-- Return note's icon path, given a particular db.  Needed
-- because some note databases don't have the usual note table data (e.g.
-- Cartographer_Mailboxes).
local
function getNoteIconPath(dbName, note)
    local path = dbName2noteIconPathOverrideFn[dbName] and
                   dbName2noteIconPathOverrideFn[dbName](note) or
                        iconList[note.icon].path

    -- Use standalone copies of the raid targetting icons because Dewdrop
    -- check mark icons cannot be created from a portion of a texture.
    if path == "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
    then
        path = "Interface\\Addons\\Cartographer_Sidelist\\textures\\" ..
                    note.icon
    end

    return path
end     -- getNoteIconPath


-- Mapping of special-case dbName's to info needed to get the note's title.
-- An entry in this mapping implies note does not have the usual title field
-- or it needs to be overridden.
local dbName2noteTitleOverrideFn = {
    -- nnTrainers creates notes where 'info' contains the trainer's name and
    -- 'title' is the trainer type.  'title' is not always set, so this
    -- clearly causes issues when trying to get the note's title.  We return
    -- a title comprised of both.
    nnTrainers = function(note)
            local trainerType = note.title or ""
            if Cartographer_Sidelist.db.profile.smartSort
            then
                return (Cartographer_Sidelist.db.profile.showType and
                        trainerType .. " - " or
                        "") .. note.info
            end

            return note.info ..
                    (Cartographer_Sidelist.db.profile.showType and
                        " - " .. trainerType or
                        "")
        end,
    -- Fishing, Herbalism and Mining notes don't have a title--the note
    -- object is the title.
    Fishing = function(note)
            return note
        end,
    Herbalism = function(note)
            return note
        end,
    Mining = function(note)
            return note
        end,
    Mailboxes = function(note)
            return "Mailbox"
        end,
    Trainers = function(note)
            local trainerType = note.info or ""
            if Cartographer_Sidelist.db.profile.smartSort
            then
                return (Cartographer_Sidelist.db.profile.showType and
                        trainerType .. " - " or
                        "") .. note.title
            end

            return note.title ..
                    (Cartographer_Sidelist.db.profile.showType and
                        " - " .. trainerType or
                        "")
        end,
    Vendors = function(note)
            local vendorType = note.info or ""
            if Cartographer_Sidelist.db.profile.smartSort
            then
                return (Cartographer_Sidelist.db.profile.showType and
                        vendorType .. " - " or
                        "") .. note.title
            end

            return note.title ..
                    (Cartographer_Sidelist.db.profile.showType and
                        " - " .. vendorType or
                        "")
        end,
}

-- Return the note's title from the given note object, given a particular
-- db.  Needed because some note databases don't have the usual note table
-- data.
local
function getNoteTitle(dbName, note)
    return dbName2noteTitleOverrideFn[dbName] and
           dbName2noteTitleOverrideFn[dbName](note) or
            note.title or
            "<no note title>"       -- XXX: getting here means override map needs updating
end     -- getNoteTitle


-- Return true if the lhs note's title is alphabetically ordered before the
-- rhs note's title.  If both are equal, compare each note's ID and return
-- true if the lhs > rhs.  In all other cases, return false.
-- Each note is assumed to come from dbname database.
local
function noteComparator(dbName, lhs, rhs)
    local lhsTitle = getNoteTitle(dbName, lhs.v)
    local rhsTitle = getNoteTitle(dbName, rhs.v)

    if lhsTitle < rhsTitle
    then
        return true
    elseif lhsTitle == rhsTitle
    then
        -- To give a deterministic ordering for notes that have the same
        -- title, order them by id.
        return lhs.k < rhs.k
    end

    return false
end     -- noteComparator


-- Return the pretty category name for the given DB.  dbName of nil refers
-- to the General category.
local
function dbNameToCategory(dbName)
    local db2pretty = {
        InstanceNotes = "Instance Notes",
        POI = "Points of Interest",
        QuestObjectives = "Quest Objectives",
        ToFuNotes = "Flightmasters",
        nnTrainers = "NN Trainers",
    }

    -- If there is no key for the given DB, use dbName as-is.
    return dbName and db2pretty[dbName] or
            not db2pretty[dbName] and dbName or
            "General"
end     -- dbNameToCategory


-- Show or hide the side list tablet.
-- show - true=>show, false=>hide
local
function showTablet(self, show)
    if WorldMapFrame:IsShown()
    then
        -- In a completely, mind-fuck sort of way, you don't actually
        -- Close() the tablet.  Instead, you rely on two things:  1) the
        -- fact that the "children" function passed in at registration ONLY
        -- populates the tablet if the tablet is being shown (a property
        -- which is tracked externally, e.g. by the addon using the tablet),
        -- and 2) the "hideWhenEmpty" property passed in at registration is
        -- set to true.  This brain-fuck magic means we don't ever call
        -- Close(), we just clear the flag that says the tablet is open and
        -- then cause it to be redrawn (and since we're hiding the tablet
        -- when it's empty, and since the is-open flag is cleared, nothing
        -- gets added to the tablet, rendering it empty and thus it doesn't
        -- get shown at all!).  In fact, if you actually call Close() on the
        -- tablet, it appears to be impossible to open it again!!!  The
        -- common-sensicle thing of calling Open() seems to do nothing at
        -- all!!!  There will be murders.
        
        -- So this means we actually SET the flag that determines whether
        -- the tablet is open BEFORE we call Refresh.
        -- AAAAAAAARRRRRRRGGGGGGGGGHHHHHHH!!!!!!!

        -- Please, baby Jeebus, for the love of all that is holy, let me be
        -- completely wrong about all this.

        sidelistIsOpen = show

        -- As above, this is the most fucked up thing imaginable--even if
        -- the tablet is "closed", we actually open it and redraw it.
        -- Wheeeeeeeeee!
        Tablet:Open("SidelistTablet")
        Tablet:Refresh("SidelistTablet")
    end
end     -- showTablet


-- Return the note's frame corresponding to the given note ID.
-- XXX:  need db check?
local
function getNoteFrameById(id)
    for _, frame in ipairs({ (Cartographer:GetInstanceWorldMapButton() or
                              WorldMapButton):GetChildren() })
    do
        if frame.id == id and not frame.minimap
        then
            return frame
        end
    end

    return nil
end     -- getNoteFrameById


----------- Methods ----------- 


function Cartographer_Sidelist:OnInitialize()
    self.author = "Sekuyo"
    self.category = "Map"
    self.email = "sekuyo13@gmail.com"
    self.license = "GPL v2"
    self.name = "Cartographer_Sidelist"
    self.notes = "Toggle list of map notes in current zone"
    self.title = "Cartographer_Sidelist"
    self.version = "(pre-alpha)"
    self.website = "http://code.google.com/p/sekuyo-wow/"


    self.db = Cartographer:AcquireDBNamespace("Sidelist")

    Cartographer:RegisterDefaults("Sidelist", "profile",
    {
        side = "RIGHT",
        isOpen = true,
        showCoords = false,
        smartSort = true,
        showType = true,
    })

    local sidelistArgs =
    {
        toggleSide = {
            name = "Right side",
            desc = "Show sidelist on left/right",
            type = "toggle",
            get = function()
                    return self.db.profile.side == "RIGHT"
                end,
            set = function(v)
                local wasOpen = sidelistIsOpen

                if wasOpen
                then
                    showTablet(self, false)
                end

                self.db.profile.side =
                    self.db.profile.side == "RIGHT" and "LEFT" or "RIGHT"

                if wasOpen
                then
                    showTablet(self, true)
                end
            end,
            guiNameIsMap = true,
            map = {
                [true] = "Right side",
                [false] = "Left side",
            }
        },
        showSidelist = {
            name = "Show sidelist",  -- set properly on UPDATE_BINDINGS event
            desc = "Show or hide the sidelist",
            type = "toggle",
            get = function()
                    return sidelistIsOpen
                end,
            set = function(v)
                    self:ToggleSidelist()
            end,
        },
        showDBs = {
            name = "Databases to Show",
            desc = "Specify note databases that should appear in the sidelist",
            type = "group",
            args = { },     -- filled in Cartographer_MapOpened
        },
        smartSort = {
            name = "Sort vendors/trainers by type",
            desc = "Vendors and trainers are sorted by type, then name",
            type = "toggle",
            get = function()
                    return self.db.profile.smartSort
                end,
            set = function(v)
                self.db.profile.smartSort = not self.db.profile.smartSort
                showTablet(self, sidelistIsOpen)    -- refresh list
                end,
            disabled = function()
                -- Only enable smart sort option if trainer/vendor types are
                -- enabled.
                return not Cartographer.options.args.Sidelist.args.showType.get()
                end,
            usage = "Only applies if 'show type' option is enabled.",
        },
        showType = {
            name = "Show type of vendor and trainer",
            desc = "Include vendor's or trainer's type with its name",
            type = "toggle",
            get = function()
                    return self.db.profile.showType
                end,
            set = function(v)
                self.db.profile.showType = not self.db.profile.showType
                showTablet(self, sidelistIsOpen)    -- refresh list
            end,
        },
        showCoords = {
            name = "Show coords",
            desc = "Show each note's coordinates in sidelist",
            type = "toggle",
            get = function()
                    return self.db.profile.showCoords
                end,
            set = function(v)
                    self.db.profile.showCoords = not self.db.profile.showCoords 
                    showTablet(self, sidelistIsOpen)    -- refresh list
                end,
        },
    }  -- sidelistArgs

    local cartoMenuOpts = {
        name = "Sidelist",
        desc = self.notes,
        handler = self,
        type = "group",
        args = sidelistArgs,
    }

    Cartographer.options.args.Sidelist = cartoMenuOpts
    AceLibrary("AceConsole-2.0"):InjectAceOptionsTable(self,
        Cartographer.options.args.Sidelist)

    sidelistIsOpen = self.db.profile.isOpen
end     -- Cartographer_Sidelist:OnInitialize


function Cartographer_Sidelist:OnEnable()
    self:RegisterEvent("UPDATE_BINDINGS", "OnUpdateBindings")

    self:RegisterEvent("CartographerNotes_NoteSet")
    self:RegisterEvent("CartographerNotes_NoteDeleted")

    self:RegisterEvent("Cartographer_MapOpened")
    self:RegisterEvent("Cartographer_MapClosed")
    self:RegisterEvent("Cartographer_ChangeZone")

    -- Hook map frame for clicks.
    if Cartographer:GetInstanceWorldMapButton()
    then
        self:HookScript(Cartographer:GetInstanceWorldMapButton(),
            "OnClick", "SetupSidelist")
    else
        self:RegisterEvent("Cartographer_RegisterInstanceWorldMapButton",
            function(frame)
                self:HookScript(frame, "OnClick", "SetupSidelist")
            end)
    end

    -- While we could use the side tablet that Cartographer can supply us,
    -- using our own gives us more control.
    Tablet:Register("SidelistTablet",
        "data", {},
        "children", function()
                if sidelistIsOpen
                then
                    self:drawTablet()
                end
            end,
        "clickable", true,
        "dontHook", true,
        "hint", "Left-Click to open/close categories",
        "cantAttach", true,
        "frameLevel", 11,
        "movable", false,
        "minWidth", WorldMapDetailFrame:GetWidth() / 4,
        "hideWhenEmpty", true,
        "parent", WorldMapFrame,
        "showTitleWhenDetached", true,
        "showHintWhenDetached", true,
        --"menu", { },
        "positionFunc", self.db.profile.side == "LEFT" and function(this)
            self:Debug("position func left")
            this:SetPoint("TOPLEFT", WorldMapDetailFrame, "TOPLEFT")
            this:SetPoint("BOTTOMLEFT", WorldMapDetailFrame, "BOTTOMLEFT")
        end or function(this)
            self:Debug("position func right")
            this:SetPoint("TOPRIGHT", WorldMapDetailFrame, "TOPRIGHT")
            this:SetPoint("BOTTOMRIGHT", WorldMapDetailFrame, "BOTTOMRIGHT")
        end
    )

    showTablet(self, self.db.profile.isOpen)

    -- Update config option so that the desc shows which key (if any)
    -- toggles the sidelist.
    Cartographer_Sidelist:OnUpdateBindings()

    -- Register event to throb frames.
    self:RegisterEvent("ThrobUpdate")
end     -- Cartographer_Sidelist:OnEnable


-- Handler called when UPDATE_BINDINGS is fired.  Used to update the config
-- option description to indicate which key is used to toggle the sidelist.
function Cartographer_Sidelist:OnUpdateBindings()
    local key1, key2 = GetBindingKey("CARTOGRAPHER_SIDELIST_TOGGLE")

    Cartographer.options.args.Sidelist.args.showSidelist.name =
        "Show sidelist of notes (<" ..
            (key1 or key2 or "no key bound") .. ">)"
end     -- Cartographer_Sidelist:OnUpdateBindings


-- Handler to set up sidelist tablet
function Cartographer_Sidelist:SetupSidelist(frame, mouseButton)
    return self.hooks[frame].OnClick(frame, mouseButton)
end


-- Populate the tablet with categories and notes for the currently viewed
-- zone.
-- A curious point:  you have to draw all content within categories
-- yourself because there is no concept of a tree control within the tablet.
-- Hence, keeping track of which categories are "open".
function Cartographer_Sidelist:drawTablet()
    local zone = Cartographer:GetCurrentEnglishZoneName()

    Tablet:SetTitle(string.format("Notes for %s",
        Cartographer:GetCurrentEnglishZoneName()))

    -- First category is always the non-externalDB category.  It contains
    -- notes that are manually created or have been imported.
    local generalCategory = Tablet:AddCategory(
        "id", "general",
        "columns", self.db.profile.showCoords and 2 or 1,
        "hideBlankLine", false,
        "text", dbNameToCategory(nil),
        "textR", 1, "textG", 1, "textB", 0,
        "wrap", true,
        "func", function()
                categoryOpen.general = not categoryOpen.general
                showTablet(self, true)
            end,
        "showWithoutChildren", true,    -- general category always shown
        "checked", true,
        "hasCheck", true,
        "checkIcon", "Interface\\Buttons\\UI-" ..
            (categoryOpen.general and "Minus" or "Plus") .. "Button-Up"
        )

    -- Add all internal database notes to general category if it's open
    if categoryOpen.general
    then
        local noteTable = getNoteTable(zone)
        if noteTable
        then
            for id, note in orderedIter(noteTable,
                                function(lhs, rhs)
                                    return noteComparator(nil, lhs, rhs)
                                end, pairs)
            do
                -- If no titleCol is defined for the note, the color
                -- defaults to white.
                local titleR, titleG, titleB =
                    Cartographer_Notes.getRGB(note.titleCol)

                generalCategory:AddLine(
                    "text", getNoteTitle(nil, note),
                    "textR", titleR, "textG", titleG, "textB", titleB,
                    "text2", self.db.profile.showCoords and
                                string.format("%.1f, %.1f",
                                    multiplyCoords(Cartographer_Notes.
                                                    getXY(id))) or "",
                    "wrap", true,
                    "func", function(id)
                                if self.throbData.id == id
                                then
                                    self:StopThrob()
                                else
                                    self:StartThrob(id)
                                end
                            end,
                    "arg1", id,
                    "checked", true,
                    "hasCheck", true,
                    "checkIcon", getNoteIconPath(nil, note),
                    "indentation", 15
                )
            end
        end     -- if general notetable exists for this zone
    end     -- if general category is open

    -- Used to ensure there is vertical space between the General category
    -- and the next category containing notes.  Set to true after the first
    -- non-general category is shown.
    local hideBlankLine = false

    -- Add categories for any external db's with notes in this zone.  Since
    -- we want the categories ordered by the "pretty" names of each external
    -- DB, our comparator must compare the database pretty names, rather
    -- than the internal names of each DB.
    for _, dbName in orderedIter(getExternalDatabaseNames(zone),
                                    function(lhs, rhs)
                                        return dbNameToCategory(lhs.v) <
                                               dbNameToCategory(rhs.v)
                                    end,
                                 ipairs)
    do
        local noteTable = getNoteTable(zone, dbName)
        local numNotes = numberOfKeys(noteTable)

        -- Only add this db as a category if it has notes for this zone, and
        -- if the user says we should show it.
        if numNotes > 0 and self.db.profile["show"..dbName]
        then
            local category = Tablet:AddCategory(
                "id", dbName,
                "columns", self.db.profile.showCoords and 2 or 1,
                "text", dbNameToCategory(dbName),
                "textR", 1, "textG", 1, "textB", 0,
                "wrap", true,
                "func", function()
                        categoryOpen[dbName] = not categoryOpen[dbName]
                        showTablet(self, true)
                    end,
                "showWithoutChildren", true,
                -- 1st category needs leading blank line to separate it from
                -- the General category
                "hideBlankLine", hideBlankLine,
                "checked", true,
                "hasCheck", true,
                "checkIcon", "Interface\\Buttons\\UI-" ..
                    (categoryOpen[dbName] and "Minus" or "Plus") .. "Button-Up"
            )

            hideBlankLine = true

            -- Add this external database's notes to this category if it's open
            if categoryOpen[dbName]
            then
                for id, note in orderedIter(noteTable,
                                  function(lhs, rhs)
                                      return noteComparator(dbName, lhs, rhs)
                                  end, pairs)
                do
                    -- If external DB has a handler function that specifies
                    -- note visibility, call it and only create a sidelist
                    -- entry if the note is visible.
                    local handler = Cartographer_Notes.handlers[dbName]
                    if not handler or not handler.IsNoteHidden or
                       not handler:IsNoteHidden(zone, id, note)
                    then
                        -- If no titleCol is defined for the note, the color
                        -- defaults to white.
                        local titleR, titleG, titleB =
                            Cartographer_Notes.getRGB(note.titleCol)

                        category:AddLine(
                            "text", getNoteTitle(dbName, note),
                            "textR", titleR, "textG", titleG, "textB", titleB,
                            "text2", self.db.profile.showCoords and
                                        string.format("%.1f, %.1f",
                                            multiplyCoords(Cartographer_Notes.
                                                            getXY(id))) or "",
                            "wrap", true,
                            "func", function(id, db)
                                        -- XXX:  need to pass db?
                                        if self.throbData.id == id
                                        then
                                            self:StopThrob()
                                        else
                                            self:StartThrob(id)
                                        end
                                    end,
                            "arg1", id,
                            "arg2", dbName,
                            "checked", true,
                            "hasCheck", true,
                            "checkIcon",
                                getNoteIconPath(dbName, note),
                            "indentation", 15
                        )   -- AddLine
                    end     -- if handler
                end     -- for each note
            end     -- if category is open
        end     -- number of notes for this category and zone > 0
    end     -- add category for each external db
end     -- drawTablet


-- Intended for key/button binding.  Toggles the sidelist on/off if the map
-- is open.
function Cartographer_Sidelist:ToggleSidelist()
    if WorldMapFrame:IsShown()
    then
        sidelistIsOpen = not sidelistIsOpen
        showTablet(self, sidelistIsOpen)
    end
end     -- Cartographer_Sidelist:ToggleSidelist


-- Called when map is opened
function Cartographer_Sidelist:Cartographer_MapOpened()
    -- (Re)grab the list of known icons (it may have changed since we were
    -- last in here).
    iconList = Cartographer_Notes:GetIconList()

    -- Populate the Cartographer|Sidelist|"Show" submenu with each external
    -- DB name.  This is done on map open so that we can be sure any
    -- Cartographer_Notes external DBs are available.  This also allows us
    -- to notice new DBs becoming available since the last time the map was
    -- opened.
    for _, dbName in orderedIter(getExternalDatabaseNames(),
                        function(lhs, rhs)
                            return lhs.v < rhs.v
                        end, ipairs)
    do
        local key = "show" .. dbName
        if self.db.profile[key] == nil
        then
            self.db.profile[key] = true     -- default is to show
        end

        Cartographer.options.args.Sidelist.args.showDBs.args[dbName] =
        {
            name = dbNameToCategory(dbName),
            desc = "Show notes from " .. dbName .. " database",
            type = "toggle",
            get = function() return self.db.profile[key] end,
            set = function(v)
                    self.db.profile[key] =
                        not self.db.profile[key] 
                    -- Redraw tablet, since database was just added/removed
                    -- from list.
                    showTablet(self, sidelistIsOpen)
                end,
        }
    end

    -- If the sidelist was open when the map was closed, make sure it's
    -- open.
    showTablet(self, self.db.profile.isOpen)
end     -- Cartographer_Sidelist:Cartographer_MapOpened


-- Called when map is closed.
function Cartographer_Sidelist:Cartographer_MapClosed()
    self:StopThrob()

    -- Save current sidelist state
    self.db.profile.isOpen = sidelistIsOpen

    showTablet(self, false)
end     -- Cartographer_Sidelist:Cartographer_MapClosed


-- On map zone change, redraw the tablet according to the new visible zone.
-- This is also fired when the map opens.
function Cartographer_Sidelist:Cartographer_ChangeZone()
    self:StopThrob()

    if sidelistIsOpen
    then
        showTablet(self, true)
    end
end     -- Cartographer_Sidelist:Cartographer_ChangeZone


-- Called when a note is added anywhere so we can refresh the sidelist, if
-- open.
function Cartographer_Sidelist:CartographerNotes_NoteSet(zone,
                x, y, icon, creator, setNoteFromComm)
    if sidelistIsOpen
    then
        showTablet(self, true)
    end
end     -- Cartographer_Sidelist:CartographerNotes_NoteSet


-- Called when a note is deleted anywhere, so we can refresh the sidelist,
-- if open.
function Cartographer_Sidelist:CartographerNotes_NoteDeleted(zone,
    x, y, icon, db)

    -- Stop throbbing if the note deleted was throbbing.
    if self.throbData.id == Cartographer_Notes.getID(x, y)
    then
        self:StopThrob()
    end

    if sidelistIsOpen
    then
        showTablet(self, true)
    end
end     -- Cartographer_Sidelist:CartographerNotes_NoteDeleted


-- Start throbbing the frame of the note with given id.
function Cartographer_Sidelist:StartThrob(id)
    -- We only throb one frame at a time, so stop any throbbing currently
    -- going on.
    self:StopThrob()

    -- XXX: need to check if note frame is visible?
    local noteFrame = getNoteFrameById(id)

    if noteFrame
    then
        -- Save helpful data about throbbing this frame
        self.throbData.id = id
        self.throbData.frame = noteFrame
        self.throbData.scale = 2       -- frame's max scale is 2x
        self.throbData.steps = 5       -- scale from current size to 2x in 5 steps
        self.throbData.interval = 0.1  -- adjust scale every 1/10sec
        self.throbData.direction = 1   -- -1=>smaller, +1=>larger
        self.throbData.curStep = 1     -- delta multiplier to get current scale
        self.throbData.origWidth = noteFrame:GetWidth()
        self.throbData.origHeight = noteFrame:GetHeight()
        self.throbData.deltaX =
            (self.throbData.origWidth * self.throbData.scale -
             self.throbData.origWidth) / self.throbData.steps
        self.throbData.deltaY =
            (self.throbData.origHeight * self.throbData.scale -
             self.throbData.origHeight) / self.throbData.steps

        self:ThrobUpdate()
    end
end     -- Cartographer_Sidelist:StartThrob


-- Stop a frame from throbbing.  Frame's pre-throb dimensions are restored.
function Cartographer_Sidelist:StopThrob()
    -- Always cancel any outstanding throb events just in case
    -- throbData.frame has already been nil'd (somehow).
    self:CancelScheduledEvent("ThrobUpdate")

    if self.throbData.frame
    then
        self.throbData.frame:SetWidth(self.throbData.origWidth)
        self.throbData.frame:SetHeight(self.throbData.origHeight)
    end

    self.throbData = { }
end     -- Cartographer_Sidelist:StopThrob


-- Resize the throbbing frame based on whether the size is currently
-- increasing or decreasing.
function Cartographer_Sidelist:ThrobUpdate()
    local throbData = self.throbData

    if not self.throbData.frame
    then
        return
    end

    self.throbData.frame:SetWidth(self.throbData.origWidth +
        self.throbData.curStep * self.throbData.deltaX)
    self.throbData.frame:SetHeight(self.throbData.origHeight +
        self.throbData.curStep * self.throbData.deltaY)

    -- If frame size is still growing or shrinking?
    if self.throbData.curStep > 0
    then
        -- If frame is at max size, start shrinking it
        if self.throbData.curStep >= self.throbData.steps
        then
            self.throbData.direction = -1
        end

        self.throbData.curStep = self.throbData.curStep +
                                 self.throbData.direction
    else
        -- Back at original size so start again
        self.throbData.curStep = 1
        self.throbData.direction = 1
    end

    self:ScheduleEvent("ThrobUpdate", self.throbData.interval,
                       self.throbData.frame)
end     -- Cartographer_Sidelist:ThrobUpdate
