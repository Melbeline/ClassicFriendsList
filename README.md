# ClassicFriendsList

Characters in the friends list, the classic way, for WoW Forever. Forever's server keeps only Battle.net friends; this addon keeps a list of characters (yours and your friends', for the whole account) and shows them in the game's friends list.

**FR** — Des personnages dans la liste d'amis, à l'ancienne, pour WoW Forever.

- **Fenêtre « Ajouter un ami » de la 1.15, deux lignes** : le bouton **Ajouter un ami** du jeu ouvre sa fenêtre dans le look du client 1.15.
  - Elle reprend le titre « Add Friend » avec son « ? », l'icône Battle.net et celle de ta faction avec « OU » entre les deux, le cadre doré, et les boutons rouges **Add Friend** et **Cancel**.
  - **La ligne du haut est celle du jeu**, seulement déplacée : un BattleTag, ou un nom envoyé à la manière de Forever (une demande d'ami), par sa propre touche Entrée et son propre bouton. Le code du jeu reste intact, car le jeu interdit à un addon d'envoyer une demande d'ami.
  - **La ligne du bas est celle de l'addon**, avec son titre au-dessus (« Ligne de l'addon ClassicFriendsList ») et le texte « Nom du perso : ami classique ». Elle ajoute un personnage à la liste tout de suite, sans demande, avec les suggestions du champ **À** du courrier (tes personnages compris). Entrée ou **Add Friend** l'ajoute (« … ajouté(e) à vos amis. ») et ferme la fenêtre.
  - Si les deux lignes sont remplies, le bouton du jeu envoie celle du haut, puis l'addon ajoute celle du bas.
  - **Tab** passe d'une ligne à l'autre. La page « ? » reste celle du jeu.
  - Le nom à donner est le **prénom et le nom** du personnage : sur Forever, c'est le nom complet qui désigne un personnage, le prénom seul n'en trouve aucun.
- **Dans la liste d'amis** : dans la fenêtre d'amis par défaut de Forever (la nouvelle fenêtre sociale), les personnages sont **dans sa liste, après tes amis Battle.net connectés et avant ceux hors ligne**, chacun sur une carte du jeu, **tout sur une ligne comme dans la liste 1.x** : « Charlotte Moon, Level 26 Priest », la zone (ou depuis quand il n'a pas été vu) en dessous ; la barre de recherche les filtre aussi. **Le nom d'un personnage connecté est à la couleur de sa classe** (sur sa carte, sa ligne et son infobulle), dès que sa classe est connue (son ClassicFriendsList ou sa Clara l'a dite) ; hors ligne, il reste gris comme le jeu. Ils y sont mis pendant que le jeu construit sa liste, avant qu'il la mette en page, et une carte Battle.net passe toujours avant eux : sans ça le jeu bloquerait ensuite sa propre recherche d'amis. Dans l'ancienne fenêtre d'amis (celle de ClassicUI), ils apparaissent **au-dessus des amis Battle.net hors ligne**, dans le style des lignes du jeu. **Connectés ou non** :
  - Connectés : le niveau, la classe et la zone (quand le personnage a lui aussi ClassicFriendsList ou Clara, et toi dans sa liste).
  - Hors ligne : depuis quand il n'a pas été vu.
  - Survol : son infobulle. **Clic droit** : **chuchoter**, **inviter** ou **retirer de la liste**.
- **Connecté ou non** : l'addon interroge le serveur sur chacun à tour de rôle, par un message d'addon chuchoté que son joueur **ne voit pas**.
  - Le rythme : une question par seconde, chacun toutes les 10 secondes, toutes les 3 quand la liste d'amis est ouverte. Tout le monde est interrogé d'un coup à la connexion et à l'ouverture de la liste.
  - Hors ligne, le serveur répond « No player named … is currently playing » : cette ligne est **cachée du chat** quand elle répond à la question de l'addon. Connecté, il ne répond rien (2 secondes de silence).
  - Un personnage entendu dans le chat (chuchotement, canal, dire, crier, guilde, groupe, raid) est connecté aussitôt.
  - Un personnage de l'autre faction apparaît toujours hors ligne : le serveur le dit introuvable.
- **Aussitôt entre deux joueurs qui ont ClassicFriendsList ou Clara** et chacun l'autre dans sa liste.
  - **Les deux addons parlent la même langue**, les mêmes messages. L'addon salue dès que le monde s'affiche (moins d'une seconde), répond aussitôt aux saluts avec niveau, classe et zone, et dit au revoir à la déconnexion (pas pendant un `/reload`).
  - Il ne répond qu'aux personnages de sa liste.
- **Connexions et déconnexions** : le chat les annonce comme pour un ami (« … s'est connecté », « … s'est déconnecté »), avec une dizaine de secondes de retard au plus, aussitôt entre deux addons.
- **Ajouts et retraits** : une ligne système jaune, comme pour un ami (« Melbeline Moon added to friends. », « … is already your friend. », « … removed from friends. »), avec les mots du jeu dans sa langue. Le nom prend l'écriture du jeu (majuscules) dès qu'il est entendu en entier.
- **`/cfl`** (ou `/classicfriendslist`) : `/cfl add Prénom Nom`, `/cfl remove Prénom Nom`, `/cfl list`.
- **`/rl`** recharge l'interface (comme `/reload`).
- **Avec Clara** : Clara contient déjà ce module, avec la même liste, les mêmes lignes et la même fenêtre. Si Clara est chargé, ClassicFriendsList **reste éteint** (une ligne dans le chat le dit) et garde sa propre liste pour le jour où Clara n'est plus là.
- La liste est gardée dans `ClassicFriendsListDB`, pour tout le compte.

**EN**
- **The 1.15 Add Friend window, two lines**: the game's **Add Friend** button opens its window in the 1.15 client's look.
  - It has the "Add Friend" title with its "?", the Battle.net and faction icons with "OR" between, the gold border, and the red **Add Friend** and **Cancel** buttons.
  - **The top line is the game's**, only moved: a BattleTag, or a name sent the Forever way (a friend request), by its own Enter and button. The game's code is untouched: the game lets no addon send a friend request.
  - **The bottom line is the addon's**, with its title above it ("ClassicFriendsList addon's line") and the text "Character name: classic friend". It adds a character to the list at once, no request, with the mail's To suggestions. Enter or **Add Friend** adds it and shuts the window.
  - Both lines typed: the game's button sends the top one, then the addon adds the bottom one.
  - **Tab** moves between the lines. The name is the character's **first name and surname**: on Forever the whole name is what finds a character.
- **In the friends list**: in Forever's default friends window (the new social window), the characters are in its list, after your Battle.net friends online and before those offline, each on the game's card, all on one line as in the 1.x list ("Charlotte Moon, Level 26 Priest", the zone under it); the search box filters them. An online character's name is in its class color (card, row and tooltip) once its class is known; offline, the game's grey. They are put in as the game builds its list, before it lays it out, a Battle.net card always first (else the game would then block its own friend search). In the older friends window (ClassicUI's), they show above the offline Battle.net friends, in the game's row look. Online or offline:
  - Online: level, class and zone, from their own ClassicFriendsList or Clara.
  - Offline: when last seen.
  - Hover: a tooltip. Right-click: whisper, invite, remove.
- **Online or not**: an unseen addon whisper to each in turn.
  - The pace: one a second, each every 10 s, every 3 s with the list open.
  - The server's "No player named …" means offline, and that line is hidden. Silence means online.
  - A character heard in the chat is online at once.
- **At once between two players with ClassicFriendsList or Clara** (the same messages): a hello, its answer (level, class, zone) and a goodbye at logout (not at a reload).
- **Comings and goings**, additions and removals: said in the chat as the game says them for a friend.
- **`/cfl add First Surname`**, **`/cfl remove First Surname`**, **`/cfl list`**. **`/rl`** reloads the interface (as `/reload`).
- **With Clara loaded**, ClassicFriendsList stays off: Clara has the same module. One chat line says so.

Install: copy the `ClassicFriendsList` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
