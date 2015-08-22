for fichier in *.gz.aes
do
    echo "Traitement de $fichier... "
    openssl aes-256-cbc -d -salt -in $fichier -out $(echo $fichier | sed s/.aes//g)
    gunzip $(echo $fichier | sed s/.aes//g)
    rm $fichier
done

exit 0