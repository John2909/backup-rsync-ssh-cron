# Sauvegarde sécurisée et restauration d'un serveur Linux (rsync + SSH + cron)

Solution de sauvegarde **automatique, sécurisée et testée** d'un serveur Linux vers un serveur de sauvegarde distant, réalisée avec les outils natifs d'Ubuntu Server : `rsync`, `SSH`, `cron` et des scripts `bash`.

> Projet Personnel.

## Sommaire

1. [Objectifs](#objectifs)
2. [Architecture](#architecture)
3. [Prérequis](#prérequis)
4. [Structure du dépôt](#structure-du-dépôt)
5. [Installation pas à pas](#installation-pas-à-pas)
6. [Utilisation](#utilisation)
7. [Sécurité](#sécurité)
8. [Problèmes rencontrés](#problèmes-rencontrés)
9. [Limites et améliorations](#limites-et-améliorations)
10. [Auteur](#auteur-et-licence)

\---

## Objectifs

* Mettre en place une sauvegarde **automatique** (planifiée avec cron)
* Utiliser uniquement des **outils Linux natifs**
* **Sécuriser** le transfert et l'accès au serveur de sauvegarde
* Stocker les copies sur un **serveur distant**
* **Tester la restauration** des données
* **Journaliser** chaque opération et détecter les échecs

## Architecture

```
┌──────────────────────┐                         ┌──────────────────────┐
│   srv-principal      │                         │     srv-backup       │
│   192.168.100.113    │   rsync via SSH         │   192.168.100.114    │
│                      │ ───────────────────────►│                      │
│   /srv/data          │   (clé Ed25519,         │   /backup/data       │
│   backup.sh + cron   │    port 22)             │   utilisateur :      │
│   restore.sh         │ ◄───────────────────────│   backupuser         │
└──────────────────────┘   restauration          └──────────────────────┘
```

|Machine|Rôle|Système|Utilisateur|Dossier|
|-|-|-|-|-|
|`srv-principal`|Héberge les données, exécute la sauvegarde|Ubuntu Server|`srv-principal`|`/srv/data`|
|`srv-backup`|Stocke les copies|Ubuntu Server|`backupuser`|`/backup/data`|

Les deux machines sont des machines virtuelles vmware en mode **Accès par pont**.

!\[Les deux machines virtuelles](docs/images/01-vms-vmware.png)

## Prérequis

* 2 machines (ou VM) sous Ubuntu Server, sur le même réseau
* Accès `sudo` sur les deux
* Paquets `rsync` et `openssh-server` installés sur les deux machines

```bash
sudo apt update \\\&\\\& sudo apt install -y rsync openssh-server
```

## Structure du dépôt

```
.
├── README.md
├── scripts/
│   ├── backup.sh            # Sauvegarde (rsync + log)
│   ├── restore.sh           # Restauration
│   └── check-backup.sh      # Vérifie la fraîcheur de la dernière sauvegarde
├── config/
│   ├── crontab.example      # Planification
│   ├── logrotate-backup     # Rotation des logs
│   ├── sshd-hardening.conf  # Durcissement SSH (srv-backup)
│   ├── authorized\\\_keys.example
│   └── ufw-rules.sh         # Pare-feu (srv-backup)
└── docs/images/             # Captures d'écran
```

\---

## Installation pas à pas

### 1\. Préparer le réseau

Renommer les machines, fixer les IP (netplan) et vérifier la communication.

```bash
# srv-principal
sudo hostnamectl set-hostname srv-principal
# srv-backup
sudo hostnamectl set-hostname srv-backup

# Exemple /etc/netplan/\\\*.yaml pour srv-backup (adapter l'interface et la passerelle)
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: false
      addresses: \\\[192.168.100.114/24]
      routes:
        - to: default
          via: 192.168.100.1
      nameservers:
        addresses: \\\[1.1.1.1, 8.8.8.8]

sudo netplan apply
ping -c 4 192.168.100.114     # depuis srv-principal
ping -c 4 192.168.100.113     # depuis srv-backup
```

!\[Ping entre les serveurs](docs/images/02-ping-entre-serveurs.png)

### 2\. Dossier de données et serveur de sauvegarde

Sur **srv-principal** :

```bash
sudo mkdir -p /srv/data
sudo chown $USER:$USER /srv/data
sudo chmod 755 /srv/data
echo "Document 1" > /srv/data/fichier1.txt
echo "Document 2" > /srv/data/fichier2.txt
```

!\[Données source](docs/images/03-donnees-source.png)

Sur **srv-backup** :

```bash
sudo adduser --gecos "" backupuser
sudo mkdir -p /backup/data
sudo chown -R backupuser:backupuser /backup
sudo chmod 700 /backup
```

!\[Configuration du serveur de sauvegarde](docs/images/04-serveur-backup-config.png)

### 3\. Connexion SSH par clé

Sur **srv-principal** :

```bash
ssh-keygen -t ed25519 -C "backup-srv-principal"
ssh-copy-id backupuser@192.168.100.114
ssh backupuser@192.168.100.114 "hostname \\\&\\\& whoami"   # aucun mot de passe demandé
```

!\[Génération de la clé](docs/images/05-ssh-keygen.png)
!\[Copie de la clé](docs/images/06-ssh-copy-id.png)
!\[Connexion sans mot de passe](docs/images/07-connexion-ssh-sans-mdp.png)

> La clé n'a volontairement pas de passphrase, afin que cron puisse l'utiliser. Les risques sont réduits à l'étape 8.

### 4\. Script de sauvegarde

Le script est dans [`scripts/backup.sh`](scripts/backup.sh) et s'installe dans `/usr/local/bin/`.

```bash
sudo mkdir -p /var/log/backup
sudo chown $USER:$USER /var/log/backup
sudo cp scripts/backup.sh /usr/local/bin/backup.sh
sudo chown root:root /usr/local/bin/backup.sh
sudo chmod 755 /usr/local/bin/backup.sh
```

Points clés du script :

* `rsync -az --stats` : copie incrémentielle, avec compression pendant le transfert
* `flock` : empêche deux sauvegardes simultanées
* `BatchMode=yes` et `ConnectTimeout=10` : SSH n'attend jamais de saisie et abandonne vite si `srv-backup` est injoignable
* un seul fichier de log, `BACKUP OK` ou `BACKUP ECHEC (code N)` à chaque passage
* aucune option `--delete` : un fichier supprimé sur la source reste disponible sur la sauvegarde

!\[Script de sauvegarde](docs/images/08-script-backup.png)
!\[Test manuel](docs/images/09-test-manuel.png)

### 5\. Automatisation avec cron

```bash
crontab -e
```

```
# Sauvegarde quotidienne à 05h00
0 5 \\\* \\\* \\\* /usr/local/bin/backup.sh

# Vérification quotidienne à 08h00
0 8 \\\* \\\* \\\* /usr/local/bin/check-backup.sh >> /var/log/backup/check.log 2>\\\&1
```

Pendant les tests, la fréquence était de `\\\*/5 \\\* \\\* \\\* \\\*` (toutes les 5 minutes). La rotation des logs est gérée par [`config/logrotate-backup`](config/logrotate-backup) (hebdomadaire, 4 archives compressées).

!\[Crontab](docs/images/10-crontab.png)
!\[Logs générés par cron](docs/images/11-logs-cron.png)

### 6\. Test de sauvegarde

```bash
echo "test backup" > /srv/data/test.txt        # sur srv-principal
# attendre le passage de cron, puis sur srv-backup :
sudo -u backupuser cat /backup/data/test.txt
sha256sum /srv/data/test.txt                    # comparer les empreintes des deux côtés
```

!\[Fichier créé sur la source](docs/images/12-test-source.png)
!\[Fichier arrivé sur la destination](docs/images/13-test-destination.png)

### 7\. Test de restauration

```bash
rm /srv/data/test.txt
rsync -avun backupuser@192.168.100.114:/backup/data/ /srv/data/   # simulation
rsync -avu  backupuser@192.168.100.114:/backup/data/ /srv/data/   # restauration
sha256sum /srv/data/test.txt                                    # identique à l'original
```

!\[Suppression](docs/images/14-suppression.png)
!\[Restauration](docs/images/15-restauration.png)
!\[Vérification](docs/images/16-verification.png)

Un script [`scripts/restore.sh`](scripts/restore.sh) rend l'opération plus sûre en situation de panne (`restore.sh --dry-run` pour simuler).

!\[Script de restauration](docs/images/17-restore-script.png)

### 8\. Durcissement de la sécurité

Sur **srv-backup** :

* **Clé SSH restreinte** dans `authorized\\\_keys` : utilisable uniquement depuis `192.168.100.113`, sans terminal ni redirection de ports ([exemple](config/authorized_keys.example))
* **Authentification par mot de passe désactivée** ([`config/sshd-hardening.conf`](config/sshd-hardening.conf))
* **Pare-feu UFW** : seul SSH depuis `srv-principal` est autorisé ([`config/ufw-rules.sh`](config/ufw-rules.sh))

!\[Clé restreinte](docs/images/18-authorized-keys.png)
!\[Durcissement SSH](docs/images/19-sshd-hardening.png)
!\[Pare-feu](docs/images/20-ufw-status.png)
!\[Journal SSH](docs/images/21-journal-ssh.png)

### 9\. Test d'échec et supervision

`srv-backup` a été éteint pour vérifier que l'échec est bien enregistré, puis rallumé : la sauvegarde a rattrapé son retard sans perte de données.

!\[Échec de sauvegarde](docs/images/22-echec-sauvegarde.png)

Le script [`scripts/check-backup.sh`](scripts/check-backup.sh) contrôle l'âge de la dernière sauvegarde réussie :

|Code de retour|Signification|
|-|-|
|`0`|OK|
|`1`|Dernière sauvegarde réussie trop ancienne|
|`2`|Aucune sauvegarde réussie dans le log|
|`3`|Date illisible dans le log|

!\[Vérification de la sauvegarde](docs/images/23-check-backup.png)
!\[Crontab de production](docs/images/24-crontab-production.png)

\---

## Utilisation

|Action|Commande|
|-|-|
|Lancer une sauvegarde manuelle|`/usr/local/bin/backup.sh`|
|Consulter le journal|`tail -n 30 /var/log/backup/backup.log`|
|Vérifier l'état de la dernière sauvegarde|`check-backup.sh`|
|Simuler une restauration|`restore.sh --dry-run`|
|Restaurer|`restore.sh`|
|Comparer source et sauvegarde|`rsync -avcn /srv/data/ backupuser@192.168.100.114:/backup/data/` (liste vide = identiques)|

## Sécurité

|Mesure|Mise en place|Risque réduit|
|-|-|-|
|Transfert chiffré|rsync via SSH|Écoute du réseau|
|Authentification par clé|Ed25519, mot de passe SSH désactivé|Attaque par force brute|
|Clé restreinte|`from=`, `no-pty`, pas de forwarding|Utilisation détournée de la clé volée|
|Compte dédié|`backupuser`, `/backup` en `700`|Accès d'autres utilisateurs|
|Pare-feu|UFW, SSH depuis une seule IP|Accès depuis d'autres machines|
|Journalisation|`backup.log`, `journalctl -u ssh`|Détection et audit|

**Ce qui n'est pas protégé :**

* La clé privée n'a pas de passphrase : si `srv-principal` est compromis, l'attaquant peut écrire sur `srv-backup` (dans les limites des restrictions ci-dessus).
* Les données sont chiffrées **pendant le transfert**, pas **au repos** sur le disque de `srv-backup`.

## Problèmes rencontrés

|Problème|Cause|Solution|
|-|-|-|
|`Permission denied (publickey,password)`|Clé SSH non installée sur `srv-backup`|`ssh-copy-id`, puis vérification des droits de `\\\~/.ssh`|
|Cron n'exécutait pas la sauvegarde|Le script écrivait dans `/var/log` sans les droits, et la clé SSH n'était pas celle de l'utilisateur de cron|Dossier `/var/log/backup` appartenant à l'utilisateur, et tâche cron lancée avec l'utilisateur qui possède la clé|
|`Permission denied` sur `/srv/data`|Dossier créé avec `sudo`, donc propriété de root|`sudo chown $USER:$USER /srv/data`|
|Cron bloqué à la première connexion|L'empreinte du serveur n'avait jamais été acceptée (`known\\\_hosts`)|Première connexion SSH manuelle, avec `yes`|
|Des dizaines de fichiers de log|Un fichier par exécution toutes les 5 minutes|Un seul fichier, avec `logrotate`|
|`check-backup.sh` : `date: invalid date` puis `syntax error: operand expected`|Extraction de la date par `sed` qui échouait, la variable restait vide|Extraction avec `grep -oE` et vérification du résultat avant le calcul|
|`PTY allocation request failed` après la restriction de la clé|Comportement voulu : `no-pty` interdit les sessions interactives|Administrer `srv-backup` via un autre compte ou la console|

## Limites et améliorations

**Limites actuelles**

* Pas de **versionnage** : une copie corrompue écrase la bonne au passage suivant
* Pas de **chiffrement des données au repos**
* Pas de **notification** automatique en cas d'échec (le script `check-backup.sh` est prêt, mais personne n'est prévenu)
* Une seule copie, sur un seul site

**Améliorations possibles**

* Sauvegardes versionnées avec `rsync --link-dest` (instantanés quotidiens)
* Alertes par e-mail ou webhook à partir des codes de retour de `check-backup.sh`
* Chiffrement des sauvegardes (par exemple avec `borgbackup` ou `restic`)
* Copie hors site (cloud ou second site)
* Supervision (Zabbix, Uptime Kuma…)
* Passphrase sur la clé avec `ssh-agent` ou authentification par certificat SSH

## Auteur

* **Auteur :** MBOUYOM NAOUSSI STEVE LIONEL

