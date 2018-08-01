#
# Copyright (C) 2011 OpenWrt.org
#

PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1

CI_BLKSZ=65536
CI_LDADR=0x80060000

PLATFORM_DO_UPGRADE_COMBINED_SEPARATE_MTD=0

platform_find_partitions() {
	local first dev size erasesize name
	while read dev size erasesize name; do
		name=${name#'"'}; name=${name%'"'}
		case "$name" in
			vmlinux.bin.l7|vmlinux|kernel|linux|linux.bin|rootfs|filesystem)
				if [ -z "$first" ]; then
					first="$name"
				else
					echo "$erasesize:$first:$name"
					break
				fi
			;;
		esac
	done < /proc/mtd
}

platform_find_kernelpart() {
	local part
	for part in "${1%:*}" "${1#*:}"; do
		case "$part" in
			vmlinux.bin.l7|vmlinux|kernel|linux|linux.bin)
				echo "$part"
				break
			;;
		esac
	done
}

platform_find_rootfspart() {
	local part
	for part in "${1%:*}" "${1#*:}"; do
		[ "$part" != "$2" ] && echo "$part" && break
	done
}

platform_check_combined() {
	[ "$magic" != "4349" ] && {
		echo "Invalid image. Use proper *-sysupgrade.bin file for this board"
		return 1
	}

	return 0
}

platform_do_upgrade_combined() {
	local partitions=$(platform_find_partitions)
	local kernelpart=$(platform_find_kernelpart "${partitions#*:}")
	local erase_size=$((0x${partitions%%:*})); partitions="${partitions#*:}"
	local kern_length=0x$(dd if="$1" bs=2 skip=1 count=4 2>/dev/null)
	local kern_blocks=$(($kern_length / $CI_BLKSZ))
	local root_blocks=$((0x$(dd if="$1" bs=2 skip=5 count=4 2>/dev/null) / $CI_BLKSZ))

	if [ -n "$partitions" ] && [ -n "$kernelpart" ] && \
	   [ ${kern_blocks:-0} -gt 0 ] && \
	   [ ${root_blocks:-0} -gt 0 ] && \
	   [ ${erase_size:-0} -gt 0 ];
	then
		local rootfspart=$(platform_find_rootfspart "$partitions" "$kernelpart")
		local append=""
		[ -f "$CONF_TAR" -a "$SAVE_CONFIG" -eq 1 ] && append="-j $CONF_TAR"

		if [ "$PLATFORM_DO_UPGRADE_COMBINED_SEPARATE_MTD" -ne 1 ]; then
		    ( dd if="$1" bs=$CI_BLKSZ skip=1 count=$kern_blocks 2>/dev/null; \
		      dd if="$1" bs=$CI_BLKSZ skip=$((1+$kern_blocks)) count=$root_blocks 2>/dev/null ) | \
			    mtd -r $append -F$kernelpart:$kern_length:$CI_LDADR,rootfs write - $partitions
		elif [ -n "$rootfspart" ]; then
		    dd if="$1" bs=$CI_BLKSZ skip=1 count=$kern_blocks 2>/dev/null | \
			    mtd write - $kernelpart
		    dd if="$1" bs=$CI_BLKSZ skip=$((1+$kern_blocks)) count=$root_blocks 2>/dev/null | \
			    mtd -r $append write - $rootfspart
		fi
	fi
	PLATFORM_DO_UPGRADE_COMBINED_SEPARATE_MTD=0
}

platform_check_image() {
	local board=$(board_name)
	local magic="$(get_magic_word "$1")"

	[ "$#" -gt 1 ] && return 1

	case "$board" in
	"ubnt,rs"|\
	"ubnt,rspro")
		platform_check_combined "$ARGV"
		;;
	*)
		return 0
		;;
	esac
}

platform_do_upgrade() {
	local board=$(board_name)

	case "$board" in
	"ubnt,rs"|\
	"ubnt,rspro")
		platform_do_upgrade_combined "$ARGV"
		;;
	*)
		default_do_upgrade "$ARGV"
		;;
	esac
}
