#!/bin/bash
#
# BacMan 1.0
# Licence GPLv3
#
# Ascii art trouvé sur : http://xsnippet.org/359701/
#
#                    ,.ood888888888888boo.,
#               .od888P^""            ""^Y888bo.
#           .od8P''   ..oood88888888booo.    ``Y8bo.
#        .odP'"  .ood8888888888888888888888boo.  "`Ybo.
#      .d8'   od8'd888888888f`8888't888888888b`8bo   `Yb.
#     d8'  od8^   8888888888[  `'  ]8888888888   ^8bo  `8b
#   .8P  d88'     8888888888P      Y8888888888     `88b  Y8.
#  d8' .d8'       `Y88888888'      `88888888P'       `8b. `8b
# .8P .88P            """"            """"            Y88. Y8.
# 88  888                                              888  88
# 88  888               B  A  C  M  A  N               888  88
# 88  888.        ..                        ..        .888  88
# `8b `88b,     d8888b.od8bo.      .od8bo.d8888b     ,d88' d8'
#  Y8. `Y88.    8888888888888b    d8888888888888    .88P' .8P
#   `8b  Y88b.  `88888888888888  88888888888888'  .d88P  d8'
#     Y8.  ^Y88bod8888888888888..8888888888888bod88P^  .8P
#      `Y8.   ^Y888888888888888LS888888888888888P^   .8P'
#        `^Yb.,  `^^Y8888888888888888888888P^^'  ,.dP^'
#           `^Y8b..   ``^^^Y88888888P^^^'    ..d8P^'
#               `^Y888bo.,            ,.od888P^'
#                    "`^^Y888888888888P^^'"

##############
# Paramètres #
##############

    # Chemins pour la sauvegarde des backups
    chemin_montage="/media/hubic/"
    chemin_backup="default/" # Le dossier « default » sera obligatoirement présent
    
    # Chiffrement des données
    activer_chiffrement=1
    extension_chiffrement=".aes"
    cle_chiffrement="M0nMöt2P@ß€!" # N'oubliez pas de le changer ^^
    
    # Login pour MySQL
    mysql_login="root" # Conseil : 
    mysql_pwd="root" # Créez un utilisateur spécial pour vos backups
    
    # Répertoires
    repertoire_temporaire="./temp/" # Faites attention à vos tmpfs, ce dossier sera très vite rempli!
    repertoire_temporaire_hubiCfuse="/tmp/" # Dossier temporaire de Hubicfuse, défini dans $HOME/.hubiCfuse (voir temp_dir), ou par défaut /tmp
    repertoire_listes="./listes/" # Ce répertoire contiendra les listes nécéssaire aux backups incrémentiels

    # Paramètres pour la sauvegarde d'un FTP distant, ainsi que pour l'upload du fichier « dump.php »
    ftp_hote="ftp.example.com" # Adresse du serveur FTP
    ftp_login="monlogin" # Login du serveur FTP
    ftp_pwd="monmotdepasse" # Mot de passe du serveur FTP
    ftp_rep="/www/dump/" # Dossier où sera uploadé « dump.php »
    
    # Paramètres pour la sauvegarde d'un serveur MySQL distant (via dump.php)
    phpsqldump_hote="localhost" # Adresse du serveur MySQL, par rapport au serveur web, donc souvent localhost!        
    phpsqldump_login="monlogin" # Login du serveur MySQL
    phpsqldump_pwd="monmotdepasse" # Mot de passe du serveur SQL
    phpsqldump_db="mabase" # Base de données à sauvegarder
    phpsqldump_url="http://example.com/~monsupersite/dump/" # Adresse à laquelle le fichier de dump sera récupérable (veuillez préciser un dossier)


###########################################
# Fonctions et variables utiles au backup #
###########################################

    # Permet d'écrire des erreurs dans STDERR
    erreur() { echo "BacMan : $@" 1>&2; }
    
    # Suffixe des backups (JJ-MM-AAAA)
    suffixe=$(date +%d-%m-%Y)
    
    # Permet une bonne rotation des logs
    lundi=$(date -dlast-monday +%Y-%m-%d) # (AAAA-MM-JJ)
    lundi_avant=$(date -d'monday-14 days' +%d-%m-%Y) # (JJ-MM-AAAA)
    lundi_avant_avant=$(date -d'monday-21 days' +%d-%m-%Y) # (JJ-MM-AAAA)
    
    # Variables permettant de sécuriser le backup SQL distant
    nom_dump_php=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1) # Merci à https://gist.github.com/earthgecko/3089509 pour la commande
    nom_dump_sql=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    cle_secrete=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
    
    # Permet de vérifier l'absence d'erreur pour chaque backup
    mysql_ok=0
    dpkg_ok=0
    conf_ok=0
    perso_ok=0
    web_ok=0
    log_ok=0
    ftp_ok=0
    sqld_ok=0

##############################################
# Désactivation du chiffrement si nécéssaire #
##############################################

    if [ $activer_chiffrement -eq 0 ]
    then
        extension_chiffrement=""
    fi
    
###########################################################################################################
# Vérification du jour de la semaine pour les sauvegardes devant s'effectuer une ou deux fois par semaine #
###########################################################################################################

    if [ "$(date +%u)" = 1 -o "$(date +%u)" = 4 ]
    then
        lundi_ou_jeudi=1
    else
        lundi_ou_jeudi=0
    fi
    
    if [ "$(date +%u)" = 1 ]
    then
        est_lundi=1
    else
        est_lundi=0
    fi

###########################
# Montage du compte hubiC #
###########################

    echo -ne "\e[34mMontage du compte hubiC...\t\t\t\t\t"

    mkdir $chemin_montage
    if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de création du dossier]"; erreur Impossible de créer le dossier pour monter le compte hubiC; exit 1; fi
    
    hubicfuse $chemin_montage -o noauto_cache,sync_read,segment_above=25000000000
    if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de montage]"; rm -r $chemin_montage; erreur Impossible de monter le compte hubiC; exit 1; fi
    
    echo -e "\e[32m[OK]"

#########################################
# Sauvegarde des bases de données MySQL #
#     Opération réalisée chaque jour    #
#########################################

    # Boucle for s'exécutant une seule fois, permettant de pouvoir sortir prématurément en cas d'erreur (grâce à un « break »)
    for controle_erreur in 0
    do
        
        echo -ne "\e[34mSauvegarde des bases de données...\t\t\t\t"
        
        mysqldump -u$mysql_login -p$mysql_pwd --all-databases > $repertoire_temporaire/backup.sql
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de dump]"; erreur Erreur lors de la génération du dump des bases de données; break; fi
        
        gzip -f $repertoire_temporaire/backup.sql
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de compression]"; erreur Erreur lors de la compression du dump des bases de données; break; fi
        
        if [ $activer_chiffrement -eq 1 ]
        then
            openssl aes-256-cbc -salt -in $repertoire_temporaire/backup.sql.gz -out $repertoire_temporaire/backup.sql.gz$extension_chiffrement -k $cle_chiffrement
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de chiffrement]"; erreur Erreur lors du chiffrement du dump des bases de données; break; fi
        fi
        
        mv $repertoire_temporaire/backup.sql.gz$extension_chiffrement $chemin_montage$chemin_backup/backup_mysql_$suffixe.sql.gz$extension_chiffrement
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de déplacement]"; erreur Erreur lors du déplacement du dump des bases de données; break; fi
        
        md5sum $chemin_montage$chemin_backup/backup_mysql_$suffixe.sql.gz$extension_chiffrement > $chemin_montage$chemin_backup/backup_mysql_$suffixe.md5
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération de la somme de contrôle]"; erreur Erreur lors de la génération de la somme de contrôle du dump des bases de données; break; fi
        
        mysql_ok=1
        
        echo -e "\e[32m[OK]"
        
    done
    
    rm $repertoire_temporaire/*

###########################################
#  Sauvegarde de la liste des programmes  #
# Opération réalisée le lundi et le jeudi #
###########################################

if [ $lundi_ou_jeudi = 1 ]
then

    for controle_erreur in 0
    do

        echo -ne "\e[34mSauvegarde de la liste des applications...\t\t\t"
        
        dpkg --get-selections > $repertoire_temporaire/backup.txt
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de dump]"; erreur Erreur lors de la génération de la liste des applications; break; fi
        
        gzip -f $repertoire_temporaire/backup.txt
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de compression]"; erreur Erreur lors de la compression de la liste des applications; break; fi
        
        if [ $activer_chiffrement -eq 1 ]
        then
            openssl aes-256-cbc -salt -in $repertoire_temporaire/backup.txt.gz -out $repertoire_temporaire/backup.txt.gz$extension_chiffrement -k $cle_chiffrement
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de chiffrement]"; erreur Erreur lors du chiffrement de la liste des applications; break; fi
        fi
        
        mv $repertoire_temporaire/backup.txt.gz$extension_chiffrement $chemin_montage$chemin_backup/backup_liste_programmes_$suffixe.txt.gz$extension_chiffrement
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de déplacement]"; erreur Erreur lors du déplacement de la liste des applications; break; fi
        
        md5sum $chemin_montage$chemin_backup/backup_liste_programmes_$suffixe.txt.gz$extension_chiffrement > $chemin_montage$chemin_backup/backup_liste_programmes_$suffixe.md5
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération de la somme de contrôle]"; erreur Erreur lors de la génération de la somme de contrôle de la liste des applications; break; fi
        
        dpkg_ok=1
        
        echo -e "\e[32m[OK]"
        
    done
    
    rm $repertoire_temporaire/*

else
    echo -e "\e[34mSauvegarde de la liste des applications...\t\e[33m[Ignoré]"
fi

#############################################
#  Sauvegarde des fichiers de configuration #
#  Opération réalisée le lundi et le jeudi  #
#############################################

if [ $lundi_ou_jeudi = 1 ]
then
    
    for controle_erreur in 0
    do

        echo -ne "\e[34mSauvegarde des fichiers de configuration...\t\t\t"
        
        tar -C / -czf $repertoire_temporaire/backup.tar.gz etc/.
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de compression]"; erreur Erreur lors de la compression des fichiers de configuration; break; fi
        
        if [ $activer_chiffrement -eq 1 ]
        then
            openssl aes-256-cbc -salt -in $repertoire_temporaire/backup.tar.gz -out $repertoire_temporaire/backup.tar.gz$extension_chiffrement -k $cle_chiffrement
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de chiffrement]"; erreur Erreur lors du chiffrement des fichiers de configuration; break; fi
        fi
        
        mv $repertoire_temporaire/backup.tar.gz$extension_chiffrement $chemin_montage$chemin_backup/backup_fichiers_configuration_$suffixe.tar.gz$extension_chiffrement
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de déplacement]"; erreur Erreur lors du déplacement des fichiers de configuration; break; fi
        
        md5sum $chemin_montage$chemin_backup/backup_fichiers_configuration_$suffixe.tar.gz$extension_chiffrement > $chemin_montage$chemin_backup/backup_fichiers_configuration_$suffixe.md5
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération de la somme de contrôle]"; erreur Erreur lors de la génération de la somme de contrôle des fichiers de configuration; break; fi
        
        conf_ok=1
        
        echo -e "\e[32m[OK]"
    
    done

    rm $repertoire_temporaire/*

else
    echo -e "\e[34mSauvegarde des fichiers de configuration...\t\e[33m[Ignoré]"
fi

#####################################
#   Sauvegarde des fichiers de log  #
# Opération réalisée tous les jours #
#####################################

    for controle_erreur in 0
    do
    
        echo -ne "\e[34mSauvegarde des fichiers de log...\t\t\t\t"
        
        tar -C / -czf $repertoire_temporaire/backup.tar.gz var/log/.
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de compression]"; erreur Erreur lors de la compression des fichiers de log; break; fi
        
        if [ $activer_chiffrement -eq 1 ]
        then
            openssl aes-256-cbc -salt -in $repertoire_temporaire/backup.tar.gz -out $repertoire_temporaire/backup.tar.gz$extension_chiffrement -k $cle_chiffrement
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de chiffrement]"; erreur Erreur lors du chiffrement des fichiers de log; break; fi
        fi
        
        mv $repertoire_temporaire/backup.tar.gz$extension_chiffrement $chemin_montage$chemin_backup/backup_fichiers_log_$suffixe.tar.gz$extension_chiffrement
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de déplacement]"; erreur Erreur lors du déplacement des fichiers de log; break; fi
        
        md5sum $chemin_montage$chemin_backup/backup_fichiers_log_$suffixe.tar.gz$extension_chiffrement > $chemin_montage$chemin_backup/backup_fichiers_log_$suffixe.md5
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération de la somme de contrôle]"; erreur Erreur lors de la génération de la somme de contrôle des fichiers de log; break; fi
        
        log_ok=1
        
        echo -e "\e[32m[OK]"
        
    done
    
    rm $repertoire_temporaire/*
    
#############################################
#     Sauvegarde des dossiers personnels    #
#  Opération réalisée le lundi et le jeudi  #
#############################################

if [ $lundi_ou_jeudi = 1 ]
then

    for controle_erreur in 0
    do
    
        echo -ne "\e[34mSauvegarde des dossiers personnels...\t\t\t\t"
        
        tar -C / -czf $repertoire_temporaire/backup.tar.gz root/. home/.
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de compression]"; erreur Erreur lors de la compression des dossiers personnels; break; fi
        
        if [ $activer_chiffrement -eq 1 ]
        then
            openssl aes-256-cbc -salt -in $repertoire_temporaire/backup.tar.gz -out $repertoire_temporaire/backup.tar.gz$extension_chiffrement -k $cle_chiffrement
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de chiffrement]"; erreur Erreur lors du chiffrement des dossiers personnels; break; fi
        fi
        
        mv $repertoire_temporaire/backup.tar.gz$extension_chiffrement $chemin_montage$chemin_backup/backup_repertoires_personnels_$suffixe.tar.gz$extension_chiffrement
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de déplacement]"; erreur Erreur lors du déplacement des dossiers personnels; break; fi
        
        md5sum $chemin_montage$chemin_backup/backup_repertoires_personnels_$suffixe.tar.gz$extension_chiffrement > $chemin_montage$chemin_backup/backup_repertoires_personnels_$suffixe.md5
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération de la somme de contrôle]"; erreur Erreur lors de la génération de la somme de contrôle des dossiers personnels; break; fi
        
        perso_ok=1
        
        echo -e "\e[32m[OK]"
        
    done
    
    rm $repertoire_temporaire/*
    
else
    echo -e "\e[34mSauvegarde des dossiers personnels...\t\t\e[33m[Ignoré]"
fi

############################################################################
#                         Sauvegarde du serveur web                        #
# Opération réalisée tous les jours, avec une sauvegarde complète le lundi #
############################################################################

    if [ $est_lundi = 1 -o ! -f $repertoire_listes/incrementiel_web.tgb ]
    then
        
        echo -ne "\e[34mSauvegarde complète du serveur web...\t\t\t\t"
        
        type="complet"
        
        if [ -f $repertoire_listes/incrementiel_web.tgb ]
        then
            rm $repertoire_listes/incrementiel_web.tgb
        fi
        
    else
        echo -ne "\e[34mSauvegarde incrémentielle du serveur web...\t\t\t"
        type="incrementiel"
    fi
    
    for controle_erreur in 0
    do
    
        tar -C / -czf $repertoire_temporaire/backup.tar.gz -g $repertoire_listes/incrementiel_web.tgb var/www/.
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de compression]"; erreur Erreur lors de la compression du serveur web; break; fi
        
        if [ $activer_chiffrement -eq 1 ]
        then
            openssl aes-256-cbc -salt -in $repertoire_temporaire/backup.tar.gz -out $repertoire_temporaire/backup.tar.gz$extension_chiffrement -k $cle_chiffrement
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de chiffrement]"; erreur Erreur lors du chiffrement du serveur web; break; fi
        fi
        
        mv $repertoire_temporaire/backup.tar.gz$extension_chiffrement $chemin_montage$chemin_backup/backup_serveur_web_$suffixe.$type.tar.gz$extension_chiffrement
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de déplacement]"; erreur Erreur lors du déplacement du serveur web; break; fi
        
        md5sum $chemin_montage$chemin_backup/backup_serveur_web_$suffixe.$type.tar.gz$extension_chiffrement > $chemin_montage$chemin_backup/backup_serveur_web_$suffixe.md5
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération de la somme de contrôle]"; erreur Erreur lors de la génération de la somme de contrôle du serveur web; break; fi
        
        web_ok=1
        
        echo -e "\e[32m[OK]"
        
    done
    
    rm $repertoire_temporaire/*

###################################
#   Sauvegarde d'un FTP distant   #
# Opération réalisée chaque lundi #
###################################

if [ $est_lundi = 1 ]
then

    for controle_erreur in 0
    do
    
        echo -ne "\e[34mSauvegarde du FTP distant...\t\t\t\t"
        
        wget -rc --quiet -P $repertoire_temporaire ftp://$ftp_login:$ftp_pwd@$ftp_hote/ > /dev/null
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de téléchargement]"; erreur Erreur lors du téléchargement d\'une copie du FTP distant; break; fi
        
        tar -czf $repertoire_temporaire/backup.tar.gz $repertoire_temporaire/$ftp_hote/.
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de compression]"; erreur Erreur lors de la compression de la sauvegarde du FTP; break; fi
        
        if [ $activer_chiffrement -eq 1 ]
        then
            openssl aes-256-cbc -salt -in $repertoire_temporaire/backup.tar.gz -out $repertoire_temporaire/backup.tar.gz$extension_chiffrement -k $cle_chiffrement
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de chiffrement]"; erreur Erreur lors du chiffrement de la sauvegarde du FTP; break; fi
        fi
        
        mv $repertoire_temporaire/backup.tar.gz$extension_chiffrement $chemin_montage$chemin_backup/backup_$ftp_hote\_$suffixe.tar.gz$extension_chiffrement
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de déplacement]"; erreur Erreur lors du déplacement de la sauvegarde du FTP; break; fi
        
        md5sum $chemin_montage$chemin_backup/backup_$ftp_hote\_$suffixe.tar.gz$extension_chiffrement > $chemin_montage$chemin_backup/backup_$ftp_hote\_$suffixe.tar.gz$extension_chiffrement.md5
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération de la somme de contrôle]"; erreur Erreur lors de la génération de la somme de contrôle de la sauvegarde du FTP; break; fi
        
        ftp_ok=1
        
        echo -e "\e[32m[OK]"
        
    done
    
    rm -r $repertoire_temporaire/*
    
else
    echo -e "\e[34mSauvegarde du FTP distant...\t\t\t\e[33m[Ignoré]"
fi

#########################################
# Sauvegarde d'un serveur MySQL distant #
#    Opération réalisée chaque lundi    #
#########################################

if [ $est_lundi = 1 ]
then

    for controle_erreur in 0
    do
    
        echo -ne "\e[34mSauvegarde du serveur MySQL distant...\t\t\t\t"
        
        # Copie du script de dump
        cp dump.php $repertoire_temporaire/$nom_dump_php.php
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de copie]"; erreur Erreur lors de la copie du script de dump du SQL distant; break; fi
    
        # Écriture des paramètres (identifiants et clés) dans la copie du script de dump
        sed -i s/"{\[DUMP_CLE\]}"/"$cle_secrete"/g $repertoire_temporaire/$nom_dump_php.php
        sed -i s/"{\[DUMP_HOTE\]}"/"$phpsqldump_hote"/g $repertoire_temporaire/$nom_dump_php.php
        sed -i s/"{\[DUMP_LOGIN\]}"/"$phpsqldump_login"/g $repertoire_temporaire/$nom_dump_php.php
        sed -i s/"{\[DUMP_PWD\]}"/"$phpsqldump_pwd"/g $repertoire_temporaire/$nom_dump_php.php
        sed -i s/"{\[DUMP_DB\]}"/"$phpsqldump_db"/g $repertoire_temporaire/$nom_dump_php.php
        sed -i s/"{\[DUMP_FICHIER\]}"/"$nom_dump_sql"/g $repertoire_temporaire/$nom_dump_php.php
        
        # Envoi du script de dump sur le serveur FTP        
ftp -n $ftp_hote <<FIN_COMMANDES_ENVOI
    user "$ftp_login" "$ftp_pwd"
    binary
    cd "$ftp_rep"
    put "$repertoire_temporaire/$nom_dump_php.php" "$nom_dump_php.php"
    bye
FIN_COMMANDES_ENVOI
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur d'envoi]"; erreur Erreur lors de l\'envoi des fichiers nécéssaires à la sauvegarde du SQL distant; break; fi

        # Génération du fichier de dump 
        wget --quiet --spider --no-check-certificate "$phpsqldump_url$nom_dump_php.php?cle=$cle_secrete" > /dev/null
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération]"; erreur Erreur lors de la génération du SQL distant; break; fi
    
        # Téléchargement du fichier de dump
        wget --quiet --no-check-certificate --output-document "$repertoire_temporaire/backup_sql_distant.sql.gz" -c "$phpsqldump_url$nom_dump_sql.sql.gz" > /dev/null
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de téléchargement]"; erreur Erreur lors du téléchargement du fichier de dump du SQL distant; break; fi
        
        # Suppression des deux fichiers du serveur FTP    
ftp -n $ftp_hote <<FIN_COMMANDES_SUPPRESSION        
    user "$ftp_login" "$ftp_pwd"
    binary
    cd "$ftp_rep"
    delete "$nom_dump_php.php"
    delete "$nom_dump_sql.sql.gz"
    bye
FIN_COMMANDES_SUPPRESSION
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de suppression]"; erreur Erreur lors de la suppression des fichiers nécéssaires à la sauvegarde du SQL distant; break; fi
        
        if [ $activer_chiffrement -eq 1 ]
        then
            openssl aes-256-cbc -salt -in $repertoire_temporaire/backup_sql_distant.sql.gz -out $repertoire_temporaire/backup_sql_distant.sql.gz$extension_chiffrement -k $cle_chiffrement
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de chiffrement]"; erreur Erreur lors du chiffrement de la sauvegarde du SQL distant; break; fi
        fi
        
        mv $repertoire_temporaire/backup_sql_distant.sql.gz$extension_chiffrement $chemin_montage$chemin_backup/backup_sql_distant_$suffixe.sql.gz$extension_chiffrement
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de déplacement]"; erreur Erreur lors du déplacement de la sauvegarde du SQL distant; break; fi
        
        md5sum $chemin_montage$chemin_backup/backup_sql_distant_$suffixe.sql.gz$extension_chiffrement > $chemin_montage$chemin_backup/backup_sql_distant_$suffixe.sql.gz$extension_chiffrement.md5
        if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de génération de la somme de contrôle]"; erreur Erreur lors de la génération de la somme de contrôle de la sauvegarde du SQL distant; break; fi
        
        sqld_ok=1
        
        echo -e "\e[32m[OK]"
        
    done
    
    rm $repertoire_temporaire/*
    
else
    echo -e "\e[34mSauvegarde du serveur MySQL distant...\t\t\e[33m[Ignoré]"
fi
    
#######################################
# Rotation des fichiers de sauvegarde #
#######################################

    if [ $mysql_ok -eq 1 ]
    then
        echo -ne "\e[34mRotation des sauvegardes des bases de données...\t\t"
        
        cd $chemin_montage$chemin_backup/
        
        if [ $(ls -1tr -I *$lundi_avant* -I *$lundi_avant_avant* backup_mysql_* | head -n -10 | wc -l) -gt 0 ]; then
            ls -1tr -I *$lundi_avant* -I *$lundi_avant_avant* backup_mysql_* | head -n -10 |  xargs -d '\n' rm
            
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur]"
            else echo -e "\e[32m[OK]"; fi
        else
            echo -e "\e[33m[Ignoré]"
        fi
    fi
    
    if [ $dpkg_ok -eq 1 ]
    then
        echo -ne "\e[34mRotation des sauvegardes de la liste des applications...\t"
        
        cd $chemin_montage$chemin_backup/
        
        if [ $(ls -1tr backup_liste_programmes_* | head -n -10 | wc -l) -gt 0 ]; then
            ls -1tr backup_liste_programmes_* | head -n -10 |  xargs -d '\n' rm
            
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur]"
            else echo -e "\e[32m[OK]"; fi
        else
            echo -e "\e[33m[Ignoré]"
        fi
    fi
    
    if [ $conf_ok -eq 1 ]
    then
        echo -ne "\e[34mRotation des sauvegardes des fichiers de configuration...\t"
        
        cd $chemin_montage$chemin_backup/
        
        if [ $(ls -1tr backup_repertoires_personnels_* | head -n -10 | wc -l) -gt 0 ]; then
            ls -1tr backup_fichiers_configuration_* | head -n -10 |  xargs -d '\n' rm        
            
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur]"
            else echo -e "\e[32m[OK]"; fi
        else
            echo -e "\e[33m[Ignoré]"
        fi
    fi
    
    if [ $perso_ok -eq 1 ]
    then
        echo -ne "\e[34mRotation des sauvegardes des dossiers personnels...\t\t"
        
        cd $chemin_montage$chemin_backup/
        
        if [ $(ls -1tr backup_repertoires_personnels_* | head -n -10 | wc -l) -gt 0 ]; then
            ls -1tr backup_repertoires_personnels_* | head -n -10 |  xargs -d '\n' rm        
            
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur]"
            else echo -e "\e[32m[OK]"; fi
        else
            echo -e "\e[33m[Ignoré]"
        fi
    fi
    
    if [ $web_ok -eq 1 ]
    then
        echo -ne "\e[34mRotation des sauvegardes du serveur web...\t\t\t"
        
        cd $chemin_montage$chemin_backup/
        
        if [ $(find . ! -newermt $lundi ! -type d  ! -name '*$lundi_avant*' ! -name '*$lundi_avant_avant*' -name 'backup_serveur_web_*' | wc -l) -gt 0 ]; then
            find . ! -newermt $lundi ! -type d  ! -name '*$lundi_avant*' ! -name '*$lundi_avant_avant*' -name 'backup_serveur_web_*' -delete
        
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur]"
            else echo -e "\e[32m[OK]"; fi
        else
            echo -e "\e[33m[Ignoré]"
        fi
    fi
    
    if [ $ftp_ok -eq 1 ]
    then
        echo -ne "\e[34mRotation des sauvegardes du FTP distant...\t\t"
        
        cd $chemin_montage$chemin_backup/
        
        if [ $(ls -1tr backup_$ftp_hote\_* | head -n -5 | wc -l) -gt 0 ]; then
            ls -1tr backup_$ftp_hote\_* | head -n -5 |  xargs -d '\n' rm
            
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur]"
            else echo -e "\e[32m[OK]"; fi
        else
            echo -e "\e[33m[Ignoré]"
        fi
    fi
    
    if [ $sqld_ok -eq 1 ]
    then
        echo -ne "\e[34mRotation des sauvegardes du serveur MySQL distant...\t\t"
        
        cd $chemin_montage$chemin_backup/
        
        if [ $(ls -1tr backup_sql_distant_* | head -n -5 | wc -l) -gt 0 ]; then
            ls -1tr backup_sql_distant_* | head -n -5 |  xargs -d '\n' rm
            
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur]"
            else echo -e "\e[32m[OK]"; fi
        else
            echo -e "\e[33m[Ignoré]"
        fi
    fi
    
    if [ $log_ok -eq 1 ]
    then
        echo -ne "\e[34mRotation des sauvegardes des fichiers de log...\t\t\t"
        
        cd $chemin_montage$chemin_backup/
        
        if [ $(ls -1tr -I *$lundi_avant* -I *$lundi_avant_avant* backup_fichiers_log_* | head -n -10 | wc -l) -gt 0 ]; then
            ls -1tr -I *$lundi_avant* -I *$lundi_avant_avant* backup_fichiers_log_* | head -n -10 |  xargs -d '\n' rm
            
            if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur]"
            else echo -e "\e[32m[OK]"; fi
        else
            echo -e "\e[33m[Ignoré]"
        fi
    fi
    
    cd /
    
#############################
# Nettoyage du compte hubiC #
#############################

    echo -ne "\e[34mNettoyage des dossiers temporaires du compte hubiC...\t\t\t"
    
    find $chemin_montage$chemin_backup/ -name "*_segments" -type d -delete # On supprime les dossiers « truc_segments », créés par hubiCfuse pour les fichiers > 1Go
    
    if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de nettoyage]"; erreur Impossible de supprimer les dossiers segments;
    else echo -e "\e[32m[OK]"; fi
        
################################################
# Nettoyage du dossier temporaire de hubiCfuse #
################################################

    echo -ne "\e[34mNettoyage du dossier temporaire de hubiCfuse...\t\t\t"
    
    find $repertoire_temporaire_hubiCfuse/ -name ".cloudfuse*" -type f -delete # On supprime les fichiers « .cloudfuse* », créés par hubiCfuse pour les fichiers uploadés
    
    if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de nettoyage]"; erreur Impossible de supprimer les fichiers temporaires cloudfuse;
    else echo -e "\e[32m[OK]"; fi

#############################
# Démontage du compte hubiC #
#############################

    echo -ne "\e[34mDémontage du compte hubiC...\t\t\t\t\t"

    umount $chemin_montage
    if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de démontage]"; erreur Impossible de démonter le compte hubiC; exit 1; fi
    
    rm -r $chemin_montage
    if [ "$?" -ne 0 ]; then echo -e "\e[31m[Erreur de suppression du dossier]"; erreur Impossible de supprimer le dossier pour monter le compte hubiC; exit 1; fi
    
    echo -e "\e[32m[OK]"

exit 0;