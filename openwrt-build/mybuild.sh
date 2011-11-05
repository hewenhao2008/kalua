#!/bin/sh

ACTION="$1"
OPTION="$2"
OPTION2="$3"
OPTION3="$4"

show_help()
{
	local me="$( basename $0 )"

	cat <<EOF
Usage:	$me gitpull
	$me select_hardware_model
	$me set_build_openwrtconfig
	$me set_build_kernelconfig
	$me applymystuff <profile> <subprofile> <nodenumber>	# e.g. "ffweimar" "adhoc" "42"
	$me make <option>
EOF
}

case "$ACTION" in
	"")
		show_help
		exit 1
	;;
	make)
		ACTION="mymake"
	;;
esac

[ -d kalua ] || {
	echo "please make sure, that your working directory is in the openwrt-base dir"
	echo "i want to see the directorys 'package', 'scripts' and 'kalua'"
	exit 1
}

log()
{
	logger -s "$1"
}

get_arch()
{
	sed -n 's/^CONFIG_TARGET_ARCH_PACKAGES="\(.*\)"/\1/p' .config		# brcm47xx|ar71xx|???
}

filesize()
{
	stat --format=%s "$1"
}

update_in_seconds()
{
	cut -d'.' -f1 /proc/uptime
}

mymake()
{
	local option="$1"			# e.g. V=99
	local t1 t2 date1 date2 hardware

	read hardware <KALUA_HARDWARE
	t1="$( update_in_seconds )"
	date1="$( date )"

	make $option

	t2="$( update_in_seconds )"
	date2="$( date )"
	echo "start: $date1"
	echo "ready: $date2"
	echo "make lasts $(( $t2 - $t1 )) seconds (~$(( ($t2 - $t1) / 60 )) min) for your '$hardware' (arch: $( get_arch ))"

	# show size of rootfs and kernel:
	# build_dir/linux-brcm47xx/root.squashfs
	# build_dir/linux-brcm47xx/vmlinux
	# build_dir/linux-brcm47xx/vmlinux.lzma
}

applymystuff()
{
	local base="package/base-files/files"
	local pwd="$( pwd )"

	log "copy apply_profile - the master controller ($( filesize kalua/openwrt-build/apply_profile ) bytes)"
	cp "kalua/openwrt-build/apply_profile" "$base/etc/init.d"

	log "copy apply_profile.code - the configurator ($( filesize kalua/openwrt-build/apply_profile.code ) bytes)"
	cp "kalua/openwrt-build/apply_profile.code" "$base/etc/init.d"

	log "copy apply_profile.definitions - your network descriptions ($( filesize kalua/openwrt-build/apply_profile.definitions ) bytes)"
	cp "kalua/openwrt-build/apply_profile.definitions" "$base/etc/init.d"

	log "copy regulatory.bin - easy bird grilling included ($( filesize kalua/openwrt-patches/regulatory.bin ) bytes)"
	cp "kalua/openwrt-patches/regulatory.bin" "$base/etc/init.d/apply_profile.regulatory.bin"

	log "copy all_the_scripts/addons - the kalua-project itself ($( du -sh kalua/openwrt-addons ))"
	cd kalua/openwrt-addons
	cp -R * "../../$base"

	cd "$pwd"
}

set_build_openwrtconfig()
{
	local config_dir file hardware

	read hardware <KALUA_HARDWARE
	config_dir="kalua/openwrt-config/hardware/$( show_known_hardware_models "$hardware" )"
	file="$config_dir/openwrt.config"
	log "applying openwrt/packages-configuration to .config ($( filesize "$file" ) bytes)"
	cp "$file" .config

	log "please launch 'make kernel_menuconfig' to stageup the kernel-dirs for architecture $( get_arch )"
	log "simply select exit and safe the config"
}

set_build_kernelconfig()
{
	local architecture kernel_config_dir file config_dir hardware

	read hardware <KALUA_HARDWARE
	config_dir="kalua/openwrt-config/hardware/$( show_known_hardware_models "$hardware" )"
	architecture="$( get_arch )"
	kernel_config_dir=build_dir/linux-${architecture}*/linux-*		# e.g. build_dir/linux-ar71xx_generic/linux-2.6.39.4
	file="$config_dir/kernel.config"
	log "applying kernel-config for arch $architecture to $kernel_config_dir/.config ($( filesize "$file" ) bytes)"
	cp "$file" $kernel_config_dir/.config
}

select_hardware_model()
{
	local specific_model="$1"
	local dir="$( dirname $0 )/../openwrt-config/hardware"
	local filename hardware i

	find "$dir/"* -type d | while read filename; do {
		hardware="$( basename "$filename" )"
		i=$(( ${i:-0} + 1 ))

		if [ -n "$specific_model" ]; then
			case "$specific_model" in
				"$i"|"$hardware")
					echo "$hardware"
				;;
			esac
		else
			echo "$i) $hardware"
		fi
	} done

	[ -z "$specific_model" ] && {
		read hardware 2>/dev/null <KALUA_HARDWARE
		echo
		echo "please select your device or hit <enter> to leave '${hardware:-empty_model}'"
		read hardware

		[ -n "$hardware" ] && {
			select_hardware_model "$hardware" >KALUA_HARDWARE
		}

		read hardware <KALUA_HARDWARE
		log "wrote model $hardware to file KALUA_HARDWARE"
	}
}

bwserver_ip()
{
	local ip

	get_ip()
	{
		ip="$( wget -qO - "http://intercity-vpn.de/networks/liszt28/pubip.txt" )"
	}

	while [ -z "$ip" ]; do {
		get_ip && {
			echo $ip
			return
		}

		log "fetching bwserver_ip"
		sleep 1
	} done
}

apply_tarball_regdb_and_applyprofile()
{
	local installation="$1"		# elephant
	local sub_profile="$2"		# adhoc
	local node="$3"			# 83
	local file

	local tarball="http://intercity-vpn.de/firmware/ar71xx/images/testing/tarball.tgz"
	local url_regdb="http://intercity-vpn.de/files/regulatory.bin"

	local pwdold="$( pwd )"
	cd package/base-files/files/

	wget -qO "tarball.tgz" "$tarball"				# tarball
	tar xzf "tarball.tgz"
	rm "tarball.tgz"

	cd etc/init.d
	wget -qO apply_profile.regulatory.bin "$url_regdb"		# regDB

	local ip_buero="$( bwserver_ip )"
	local remote_dir="Desktop/bittorf_wireless/programmierung"
	local pre="-P 222 bastian@$ip_buero"

	scp $pre:$remote_dir/etc-initd-apply_profile apply_profile
	scp $pre:$remote_dir/apply_profile-all.sh apply_profile.code

	case "$installation" in
		"")
			log "nothing to additionally apply -> generic image"
		;;
		qsoft)
			remote_dir="Desktop/bittorf_wireless/kunden/qsoft/config"
			scp $pre:$remote_dir/qsoft.csv apply_profile.csv
			scp $pre:$remote_dir/apply_config.qsoft.sh apply_profile.code

			[ "$node" ] && {
				file="/etc/init.d/apply_profile.csv"
				sed -i "s|^NODE=\"\$1\"|NODE=${node}|" apply_profile.code
				sed -i "s|^FILE=\"\$2\"|FILE=${file}|" apply_profile.code
				head -n12 apply_profile.code | tail -n4
			}
		;;
		*)
			[ "$node" ] && {
				sed -i "s/^#SIM_ARG1=/SIM_ARG1=$installation    #/" apply_profile.code
				sed -i "s/^#SIM_ARG2=/SIM_ARG2=$sub_profile    #/" apply_profile.code
				sed -i "s/^#SIM_ARG3=/SIM_ARG3=$node    #/" apply_profile.code

				local startline
				startline="$( grep -n ^"# enforcing a profile" apply_profile.code | cut -d':' -f1 )"
				startline="$(( $startline + 9 ))"
				head -n $startline apply_profile.code | tail -n 13
			}
		;;
	esac

	cd "$pwdold"

	case "$( get_arch )" in
		ar71xx)
			case "$installation" in
				rehungen*|liszt28*)
					scp $pre:$remote_dir/openwrt-patches/999-ath9k-register-reading.patch package/mac80211/patches
				;;
				*)
					[ -e "package/mac80211/patches/999-ath9k-register-reading.patch" ] && {
						rm "package/mac80211/patches/999-ath9k-register-reading.patch"
					}
				;;
			esac
		;;
		*)
			[ -e "package/mac80211/patches/999-ath9k-register-reading.patch" ] && {
				rm "package/mac80211/patches/999-ath9k-register-reading.patch"
			}
		;;
	esac
}

gitpull()
{
	log "updating package-feeds"
	cd ../packages
	git pull

	log "updating core-packages/build-system"
	cd ../openwrt
	git pull

	log "updated to openwrt-version: $( scripts/getver.sh )"
}

case "$ACTION" in
	upload)
		SERVERPATH="root@intercity-vpn.de:/var/www/firmware/$( get_arch )/images/testing/"	
		[ -n "$OPTION2" ] || SERVERPATH="$SERVERPATH/$OPTION"					# liszt28

		FILEINFO="${OPTION}${OPTION2}${OPTION3}"						# liszt28ap4
		[ -n "$FILEINFO" ] && FILEINFO="$FILEINFO-"

		case "$( get_arch )" in
			ar71xx)
				if   grep -q ^"CONFIG_TARGET_ar71xx_generic_UBNT=y" .config ; then
					LIST_FILES="            openwrt-ar71xx-generic-ubnt-bullet-m-squashfs-factory.bin"
					LIST_FILES="$LIST_FILES openwrt-ar71xx-generic-ubnt-bullet-m-squashfs-sysupgrade.bin"
				elif grep -q ^"CONFIG_TARGET_ar71xx_generic_TLWR1043NDV1=y" .config ; then
					LIST_FILES="            openwrt-ar71xx-generic-tl-wr1043nd-v1-squashfs-factory.bin"
					LIST_FILES="$LIST_FILES openwrt-ar71xx-generic-tl-wr1043nd-v1-squashfs-sysupgrade.bin"
				fi
			;;
			brcm47xx)

				# check for
				# CONFIG_TARGET_brcm47xx_Broadcom-b43=y		@ .config
				# CONFIG_TARGET_brcm47xx_Atheros-ath5k=y

				LIST_FILES="openwrt-brcm47xx-squashfs.trx openwrt-wrt54g-squashfs.bin"
			;;
		esac

		for FILE in $LIST_FILES; do {
			log "scp-ing file '$FILE' -> '${FILEINFO}${FILE}'"
			scp bin/$( get_arch )/$FILE "$SERVERPATH/${FILEINFO}${FILE}"
			WGET_URL="http://intercity-vpn.de/firmware/$( get_arch )/images/testing/${FILEINFO}${FILE}"
			log "download with: wget -O ${FILEINFO}.bin '$WGET_URL'"
		} done
	;;
	*)
		$ACTION "$OPTION" "$OPTION2" "$OPTION3"
	;;
esac

# tools:
#
# for NN in $( seq 182 228 ); do {
# 	./openwrt-firmware-bauen.sh applymystuff qsoft any "$NN"
#	./openwrt-firmware-bauen.sh make
#	./openwrt-firmware-bauen.sh upload "qsoft${NN}"
# } done
#
# ./openwrt-firmware-bauen.sh applymystuff liszt28 ap 4
#
