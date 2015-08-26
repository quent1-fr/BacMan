# BacMan
Bac(kup)Man(ager) est un script bash permettant de réaliser les sauvegardes compressées et chiffrées vers la plateforme hubiC d'OVH.
Fourni « as-is », ce script a pour but de servir de base plus ou moins solide à vos propres scripts de sauvegarde. Libre à vous d'ajouter ou de supprimer des zones à sauvegarder.
## Pré-requis

Pour fonctionner, BacMan a besoin des programmes suivant :
 
 * bash
 * tar
 * openssl (pour le chiffrement)
 * find
 * hubicfuse ([pensez à configurer ce dernier](http://www.cyrille-borne.com/forum/showthread.php?tid=97))
 * gzip
 * dpkg (pour la liste des applications)
 * mysqldump (pour la sauvegarde des bases de données MySQL)
 * wget
 * ftp (pour la sauvegarde d'une base de données MySQL distante)
 
## Installation

Placez-vous dans le dossier qui accueillera bacman (ici /opt) : 

	cd /opt

Puis clonez le dépôt : 
	
	git clone https://github.com/quent1-fr/BacMan.git bacman

Enfin, donnez les bons droits au script : 

	chmod u+x bacman/bacman.sh

## Exécution

Lancez simplement le fichier bacman.sh, avec redirection des erreurs (STDERR) dans le fichier « erreurs.log » : 

	./bacman.sh 2> erreurs.log

## Configuration

### Configuration du script
    
Avant d'exécuter le script, pensez à configurer les différents paramètres en édiant bacman.sh

### Dossiers à sauvegarder

Par défaut, bacman sauvegarde les éléments suivants :
    
* les bases de données MySQL (chaque jour, avec 10 jours de sauvegarde + les deux lundis précédent)
* la liste des applications installées (compatible Debian, deux fois par semaine, avec 10 sauvegardes gardées)
* les fichiers de configuration (/etc/*) (deux fois par semaine, avec 10 sauvegardes gardées)
* les dossiers personnels (/root/* et /home/*) (deux fois par semaine, avec 10 sauvegardes gardées)
* le serveur web (/var/www/*) (sauvegarde incrémentielle, avec rotation chaque semaine)
* les fichiers de log (/var/log/*) (chaque jour, avec 10 jours de sauvegarde + les deux lundis précédent)
    
Pour ajouter d'autres dossiers à la sauvegarde, il vous suffit de vous inspirer des éléments présents dans le code source.
    Pensez également à configurer la rotation des sauvegardes (juste avant le démontage du compte hubiC).
    
##Logiciels tiers utilisés

Pour effectuer la sauvegarde, BacMan s'appuie sur un script basé sur la librairie PHP [Shuttle Export](https://github.com/2createStudio/shuttle-export), publiée sous licence GNU GPL v2.