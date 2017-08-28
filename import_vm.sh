#!/bin/bash
###
# Script d'importation des VM Proxmox dans OpenNebula
# Ce script lit le fichier de configuration de la VM de Proxmox, importe le vdisk, créer un fichier template pour OpenNebula et l'importe.
# Liste des variables lus :
#		name:
#		cores:
#		memory:
#		
###
# Version 1.0 du 12/08/2016
###
ReplGlusterFS=/opt/replglusterfs
dedistorage=/opt/dedistorage

declare -A networks
# FrontEnd
networks[20]="FrontEnd"
# BackEnd
networks[21]="BackEnd"
# Proxylan
networks[22]="ProxyLAN"
# Yannick
networks[90]="Public Network"
# Aaron
networks[97]="Public Network"
# Dixinfor
networks[93]="Dixinfor"
# Artec
networks[94]="ARTEC"
# MagerPro
networks[91]="MAGER PRO"
# D2SAGRO
networks[88]="Public Network"
# GROUPE EA
networks[89]="Public Network"

if [ ! -z $1 ] && [ ! -z $2 ]
then
	declare -A content
	file="/opt/pve-config/qemu-server/$1.conf"
	if [ ! -r $file ]
	then
		echo "Le fichier n'existe pas ou n'est pas lisible ..."
		echo "Programme arreté"
	fi
	
	while IFS= read -r line; do
		# echo "$line"
		IFS=':' read -r key value <<< "$line"
		# echo "$key => $value"
		if [ "$key" != "" ]
		then
			content[$key]="${value#"${value%%[![:space:]]*}"}"
		fi
	done <$file

	# echo ${#content[@]}
	# @CPU @PREFIX @DISK @MEMORY @MAC @NETWORK
	echo "VM NAME: ${content[name]}"
	tmpl_file="$HOME/import_proxmox/tmpl/${content[name]}.tmpl"
	echo "TEMPLATE CIBLE: $tmpl_file" 
	if [ -a $tmpl_file ]
	then
		rm $tmpl_file
	fi
	
	# cp $HOME/import_proxmox/template.tmpl $tmpl_file
	
	for key in "${!content[@]}"
	do
		case $key in
			name)
				echo "Name is $1-${content[name]}"
				# sed -i -e "s/@NAME/$1-${content[name]}/g" $tmpl_file
				echo "NAME = $1-${content[name]}" >> $tmpl_file
				;;
			cores)
				echo "Cores Ok"
				# sed -i -e "s/@CPU/${content[cores]}/g" $tmpl_file
				echo "CPU = \"0.125\"" >> $tmpl_file
				echo "VCPU = \"${content[cores]}\"" >> $tmpl_file
				;;
			memory)
				echo "Memory Ok"
				# sed -i -e "s/@MEMORY/${content[memory]}/g" $tmpl_file
				echo "MEMORY = \"${content[memory]}\"" >> $tmpl_file
				;;
			net[0-9])
				echo "Network $key Ok"
				onevnetcmd="onevnet addar "
				# e1000=A6:D5:CA:D9:52:4E,bridge=vmbr1,tag=21
				IFS=',' read -ra values <<< "${content[$key]}"
				for i in ${!values[@]};
				do
					case ${values[$i]} in
						e1000=*)
							val=${values[$i]}
							prefix="e1000="
							mac=${val#$prefix}
							# sed -i -e "s/@MAC/$mac/g" $tmpl_file
							;;
						tag=*)
							val=${values[$i]}
							prefix="tag="
							tag=${val#$prefix}
							# network="Public Network"
							onevnetcmd+="\"${networks[$tag]}\""
							# sed -i -e "s/@NETWORK/${networks[$tag]}/g" $tmpl_file
							;;
					esac
				done

				echo "Controle si l'adresse mac existe"
				onevnetlist=`onevnet show $network`
				echo "Commande a executer: $onevnetexist"
				
				echo "Ajoute l'adresse MAC au réseau virtuel"
				onevnetcmd+=" --mac $mac --size 1"
				
				echo "Commande a executer: $onevnetcmd"
				eval $onevnetcmd
				echo "NIC = [" >> $tmpl_file
				echo "  MAC = $mac," >> $tmpl_file
				echo "  NETWORK = \"${networks[$tag]}\"," >> $tmpl_file
				echo "  NETWORK_UNAME = \"oneadmin\" ]" >> $tmpl_file
                ;;
			virtio[0-9] | ide[0-9])
				echo "Disk $key"
				## On ignore le CDROM
				if [[ "${content[$key]}" != *"media=cdrom"* ]];
				then
					echo "${content[$key]}"
					echo "DISK = [ " >> $tmpl_file

					case $key in
						virtio*)
							# sed -i -e "s/@PREFIX/vd/g" $tmpl_file
							echo "  DEV_PREFIX = vd," >> $tmpl_file
							id=${key#"virtio"}
							prefix=" --prefix vd"
							;;
						ide*)
							# sed -i -e "s/@PREFIX/hd/g" $tmpl_file
							echo "  DEV_PREFIX = hd," >> $tmpl_file
							id=${key#"ide"}
							prefix=" --prefix hd"
							;;
					esac

					diskname="${content[name]}-DISK$id"
					echo "DISKNAME=$diskname"
					# sed -i -e "s/@DISK/$diskname/g" $tmpl_file
					echo "  IMAGE = \"$diskname\"," >> $tmpl_file
					echo "  IMAGE_UNAME = \"oneadmin\" ]" >> $tmpl_file
					
					oneimagecmd="oneimage create --name $diskname"
					oneimagecmd+=$prefix
					
					# ReplGlusterFS:9001/vm-9001-disk-1.qcow2,format=qcow2,size=232G
					IFS=',' read -ra values <<< "${content[$key]}"
					for i in ${!values[@]};
					do
						case ${values[$i]} in
							format=qcow2)
								oneimagecmd+=" --driver qcow2"
								;;
							ReplGlusterFS:*)
								prefix="ReplGlusterFS:$1/"
								val=${values[$i]}
								vdisk=${val#$prefix}
								
								oneimagecmd+=" --path $ReplGlusterFS/images/$1/$vdisk"
								;;
							dedistorage:*)
								prefix="dedistorage:$1/"
								val=${values[$i]}
								vdisk=${val#$prefix}
								
								oneimagecmd+=" --path $dedistorage/images/$1/$vdisk"
								;;
							size*)
								prefix="size="
								val=${values[$i]}
								size=${val#$prefix}
								size=${size::-1}
								size=$(($size*1024))
								oneimagecmd+=" --size $size"
								;;
						esac
					done
					
					oneimagecmd+=" --datastore $2 --persistent"
					echo "Commande a executer : $oneimagecmd"
					echo "Controle si une image existe déjà"
					image_exist=`oneimage show $diskname`
					if [[ $image_exist == *"IMAGE named $diskname not found."* ]];
					then
						echo "Importation de l'image disque"
						$oneimagecmd
					else
						echo "Image existante. Arret de l'import"
						exit
					fi
				else
					echo "Exclude CDROM"
				fi
				;;
		esac
	done

	# Parametre global des templates
	echo "NIC_DEFAULT = [" >> $tmpl_file
	echo "  MODEL = \"e1000\" ]" >> $tmpl_file
	echo "CONTEXT = [" >> $tmpl_file
	echo "  NETWORK = \"YES\"," >> $tmpl_file
	echo '  SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]" ]' >> $tmpl_file
	echo "GRAPHICS = [" >> $tmpl_file
	echo "  KEYMAP = \"fr\"," >> $tmpl_file
	echo "  LISTEN = \"0.0.0.0\"," >> $tmpl_file
	echo "  TYPE = \"VNC\" ] " >> $tmpl_file
	echo "HYPERVISOR = \"kvm\" " >> $tmpl_file
	echo "OS = [" >> $tmpl_file
	echo "  ARCH = \"x86_64\" ]" >> $tmpl_file
	echo "INPUT = [" >> $tmpl_file
	echo "  BUS = \"usb\"," >> $tmpl_file
	echo "  TYPE = \"tablet\" ]" >> $tmpl_file
	
	#Import VM TEMPLATE
	echo "Importation du template"
	onetemplate create $tmpl_file
	
	#Controler si le disk est READY
	#Si oui, alors on instantie
	echo "Fin du traitement"
else
	echo "Erreur: Vous devez indiquer le numéro de la VM à migrer et le datastore a utiliser"
fi


