#!/bin/bash
# Download blockslist from http://iblocklist.com/lists.php
# add add them into Transmission

set -e

# vars
trauth=" -n username:password"
# répertoire de WORKDIR / temporaire
WORKDIR=/tmp/blocklists
# Transmission dir where to store blocklists
transmissionBlocklist=${TRANSMISSION_HOME}/blocklists
#lists to download
# bt_level1.gz bt_level2.gz france.gz
declare -a lists
lists=( "http://list.iblocklist.com/?list=ydxerpxkpcfqjaybcssw&fileformat=p2p&archiveformat=gz" "http://list.iblocklist.com/?list=gyisgnzbhppbvsphucsw&fileformat=p2p&archiveformat=gz" "http://list.iblocklist.com/?list=fr&fileformat=p2p&archiveformat=gz" )

[[ $(hostname -s) == "omvholblack" ]] && transmissionBlocklist=/srv/dev-disk-by-label-R5Store/INCOMING/transmission-home/blocklists
 
echo -e "******** Compilation d'une Blocklist pour Transmission bt client ***********"
 
echo -e "Répertoire de WORKDIR: $WORKDIR"
[[ ! -d $WORKDIR ]] && mkdir -p $WORKDIR
[[ ! -z  "$(compgen $WORKDIR/*)" ]] && rm $WORKDIR/* $transmissionBlocklist/*.bin 2>&1
 
#fetch files http://iblocklist.com/lists.php
echo -e "\n********* Téléchargements des listes de blocage *******************"
i=0
for list in ${lists[*]}; do
  i=$((i +1 ))
  echo "Downloading ${list}"
  curl -sLo $WORKDIR/lists_${i}.gz ${list}
done
#décompression
echo -e "\n********* Décompression des listes téléchargées *******************"
gunzip -fv $WORKDIR/*.gz

#concaténer les fichiers
echo -e "\n********* Création d'une seule liste sans redondance des données **"
echo -e "traitement en cours ...Patientez SVP..."
CWD=${PWD}
cd $WORKDIR
list1=$(ls) && sort -u $list1 >> blocklist &&
cd ${CWD} 

#Déplacement du fichier blocklist dans le répertoire de Transmission
echo -e "\n********* Déplacement de la Blocklist *****************************"
if [ -d $transmissionBlocklist ] ;then
    [[ -f $transmissionBlocklist/blocklist ]] && echo -e "Copie de sauvegarde de l'ancien fichier" && \
    mv -f $transmissionBlocklist/blocklist $WORKDIR/blocklist.bak || echo
    echo -e "Déplacement du nouveau fichier dans le répertoire de Transmission"
    mv -f $WORKDIR/blocklist $transmissionBlocklist/
fi
 
# Rechargement de Transmission
echo -e "Rechargement de la configuration de Transmission"
#sudo /etc/init.d/transmission-deamon reload
CMD="transmission-remote ${HOSTNAME} ${trauth} --blocklist-update"
if [[ $(hostname -s) == "omvholblack" ]]; then  
	CMD="docker-compose restart transmission"
fi
$CMD

ls $transmissionBlocklist/blocklist > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "\n***************** Opération terminée ************************************"
    echo -e "lignes: $(wc -l $transmissionBlocklist/blocklist)"
else
    echo -e "\n *** KO **** !! Le fichier bloklist est vide !! *** KO *** "
fi
