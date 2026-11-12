-- ClassicFriendsList - texts (English, then French and German)
local _, ns = ...

local L = {
  LINE_TITLE  = "ClassicFriendsList addon's line",
  FILL        = "Character name: classic friend",
  CLASSIC     = "Bottom line: added at once, no request",
  TIP         = "Adds a character to the friends list by its whole name (first name and surname), one of yours or a friend's. WoW Forever's list takes Battle.net friends only: ClassicFriendsList keeps these, for the whole account. They show above the offline Battle.net friends, online or offline: the addon asks the server about each one every 10 seconds (every 3 while the list is open), unseen by its player, and says in the chat when one comes online or goes offline, as the game does for a friend; at once between two players with ClassicFriendsList or Clara who have each other in their lists. A character of the other faction always shows offline.",
  LAST_SEEN   = "Last seen %s ago",
  ONLINE      = "Online",
  SOCIAL_HEADER = "Characters (%d/%d)",
  ROW_HINT    = "Right-click: whisper, invite, or remove from the list",
  REMOVE      = "Remove from the list",
  ADDED       = "%s added to friends.",
  REMOVED     = "%s removed from friends.",
  ALREADY     = "%s is already your friend.",
  NOT_LISTED  = "%s is not in the list.",
  CLARA       = "ClassicFriendsList: Clara is loaded and keeps this same list; ClassicFriendsList stays off.",
  HELP        = "ClassicFriendsList: /cfl add First Surname, /cfl remove First Surname, /cfl list",
  LIST_EMPTY  = "ClassicFriendsList: no character in the list.",
  LIST_HEAD   = "ClassicFriendsList: %d character(s):",
}

local locale = GetLocale and GetLocale()
if locale == "frFR" then
  L.LINE_TITLE = "Ligne de l'addon ClassicFriendsList"
  L.FILL = "Nom du perso : ami classique"
  L.CLASSIC = "Ligne du bas : ajouté aussitôt, sans demande"
  L.TIP = "Ajoute un personnage à la liste d'amis par son nom complet (prénom et nom), un des tiens ou celui d'un ami. Celle de WoW Forever ne prend que les amis Battle.net : ClassicFriendsList garde ceux-ci, pour tout le compte. Ils apparaissent au-dessus des amis Battle.net hors ligne, connectés ou non : l'addon interroge le serveur sur chacun toutes les 10 secondes (toutes les 3 quand la liste est ouverte), sans que son joueur le voie, et annonce dans le chat ses connexions et déconnexions, comme le jeu pour un ami ; aussitôt entre deux joueurs qui ont ClassicFriendsList ou Clara et chacun l'autre dans sa liste. Un personnage de l'autre faction apparaît toujours hors ligne."
  L.LAST_SEEN = "Vu il y a %s"
  L.ONLINE = "Connecté"
  L.SOCIAL_HEADER = "Personnages (%d/%d)"
  L.ROW_HINT = "Clic droit : chuchoter, inviter, ou retirer de la liste"
  L.REMOVE = "Retirer de la liste"
  L.ADDED = "%s ajouté(e) à vos amis."
  L.REMOVED = "%s retiré(e) de vos amis."
  L.ALREADY = "%s est déjà dans vos amis."
  L.NOT_LISTED = "%s n'est pas dans la liste."
  L.CLARA = "ClassicFriendsList : Clara est chargé et tient déjà cette liste ; ClassicFriendsList reste éteint."
  L.HELP = "ClassicFriendsList : /cfl add Prénom Nom, /cfl remove Prénom Nom, /cfl list"
  L.LIST_EMPTY = "ClassicFriendsList : aucun personnage dans la liste."
  L.LIST_HEAD = "ClassicFriendsList : %d personnage(s) :"
elseif locale == "deDE" then
  L.LINE_TITLE = "Zeile des Addons ClassicFriendsList"
  L.FILL = "Charaktername: klassischer Freund"
  L.CLASSIC = "Untere Zeile: sofort hinzugefügt, ohne Anfrage"
  L.TIP = "Fügt einen Charakter mit vollem Namen (Vor- und Nachname) zur Freundesliste hinzu, einen deiner oder den eines Freundes. Die von WoW Forever nimmt nur Battle.net-Freunde: ClassicFriendsList merkt sich diese, für den ganzen Account. Sie erscheinen über den Battle.net-Freunden, die offline sind, online oder offline: das Addon fragt den Server alle 10 Sekunden nach jedem (alle 3, solange die Liste offen ist), ohne dass dessen Spieler es sieht, und meldet im Chat, wann einer online kommt oder offline geht, wie das Spiel bei einem Freund; sofort zwischen zwei Spielern mit ClassicFriendsList oder Clara, die einander in ihrer Liste haben. Ein Charakter der anderen Fraktion erscheint immer offline."
  L.LAST_SEEN = "Zuletzt gesehen vor %s"
  L.ONLINE = "Online"
  L.SOCIAL_HEADER = "Charaktere (%d/%d)"
  L.ROW_HINT = "Rechtsklick: anflüstern, einladen oder aus der Liste entfernen"
  L.REMOVE = "Aus der Liste entfernen"
  L.ADDED = "%s zur Freundesliste hinzugefügt."
  L.REMOVED = "%s von der Freundesliste entfernt."
  L.ALREADY = "%s ist bereits auf deiner Freundesliste."
  L.NOT_LISTED = "%s ist nicht in der Liste."
  L.CLARA = "ClassicFriendsList: Clara ist geladen und führt dieselbe Liste; ClassicFriendsList bleibt aus."
  L.HELP = "ClassicFriendsList: /cfl add Vorname Nachname, /cfl remove Vorname Nachname, /cfl list"
  L.LIST_EMPTY = "ClassicFriendsList: kein Charakter in der Liste."
  L.LIST_HEAD = "ClassicFriendsList: %d Charakter(e):"
end

ns.L = L
