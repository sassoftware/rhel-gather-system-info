#!/bin/bash
#
# Copyright © 2022-2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# ============================
# Gather System Info
# Name: gather_info.sh
# Author: Jim Kuell, SAS <support@sas.com>
# Description: Gather and package a select set of information about a RHEL (6, 7, 8 or 9) or CentOS (6, 7 or 8) system.
# ============================
#
# USAGE
# ./gather_info.sh (parameter)
#    -h, --help       Show usage info.
#    -v, --version    Show version info.
#

set -o pipefail

# ====================================================================
# VARIABLES
# ====================================================================
GLOBAL_DATETIME="$(date +%y%m%d-%H%M%S)"
GLOBAL_SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
GLOBAL_SCRIPT_NAME="$(basename "$(readlink -f "$0")")"
GLOBAL_SCRIPT_VERSION="2.0.21"
GLOBAL_SCRIPT_BUILD_ID="202310052021"
GLOBAL_FHOST="$(hostname -f | tr -d '\040\011\012\015')"
GLOBAL_SHOST="$(hostname -s | tr -d '\040\011\012\015')"
GLOBAL_LOG_NAME="gather_info_${GLOBAL_SHOST}_${GLOBAL_DATETIME}.log"
GLOBAL_LOG_FILE="${GLOBAL_SCRIPT_DIR}/${GLOBAL_LOG_NAME}"
GLOBAL_OUTPUT_NAME="system_info_${GLOBAL_SHOST}_${GLOBAL_DATETIME}"
GLOBAL_OUTPUT_DIR="${GLOBAL_SCRIPT_DIR}/${GLOBAL_OUTPUT_NAME}"
GLOBAL_TAR_FILE="${GLOBAL_SCRIPT_DIR}/gather_info_${GLOBAL_SHOST}_${GLOBAL_DATETIME}.tar.gz"
readonly GLOBAL_DATETIME GLOBAL_SCRIPT_DIR GLOBAL_SCRIPT_NAME GLOBAL_SCRIPT_VERSION GLOBAL_SCRIPT_BUILD_ID GLOBAL_FHOST GLOBAL_SHOST GLOBAL_LOG_NAME GLOBAL_LOG_FILE GLOBAL_OUTPUT_NAME GLOBAL_OUTPUT_DIR GLOBAL_TAR_FILE
rc=0
command_output=""
warning_flag=0
error_flag=0

# ====================================================================
# INFORMATION COLLECTION VARIABLES
# ====================================================================
proc_files="cpuinfo meminfo diskstats cmdline interrupts partitions"
etc_files="redhat-release fstab multipath.conf"
etc_dirs="udev lvm"
other_files="/var/log:dmesg /boot/grub:menu.lst /etc/security:limits.conf,access.conf"
commands=("ifconfig -a"
		"getconf PAGESIZE"
		"tuned-adm list"
		"mount"
		"multipath -ll"
		"powermt version"
		"powermt display options"
		"powermt display dev=all"
		"powermt display hba_mode"
		"vxdmpadm getsubpaths"
		"vxdisk list"
		"vxddladm list devices"
		"uname -a"
		"lvs -o name,vg_name,size,attr,lv_size,stripes,stripesize,lv_read_ahead"
		"pvs"
		"vgs"
		"df -hT"
		"lscpu"
		"blockdev --report"
		"dmidecode")

# ====================================================================
# FUNCTIONS
# ====================================================================
#####
# Print version info and exit.
# Parameters:
#   None
#####
show_version() {
	echo
	echo "Gather System Info"
	echo "${GLOBAL_SCRIPT_NAME}"
	echo "Version: ${GLOBAL_SCRIPT_VERSION}"
	echo "Build: ${GLOBAL_SCRIPT_BUILD_ID}"
	echo "Copyright (c) 2022-2023 SAS Institute Inc."
	echo "Unpublished - All Rights Reserved."
	echo
	exit "${rc}"
}

#####
# Print usage info and exit.
# Parameters:
#   None
#####
show_usage() {
	echo
	echo "<<USAGE>>"
	echo "  ${GLOBAL_SCRIPT_NAME} (parameter)"
	echo
	echo "  Optional parameters:"
	echo "      -h, --help       Show usage info."
	echo "      -v, --version    Show version info."
	echo
	echo "  Function:"
	echo "      Gather and package a select set of information about a system."
	echo "      Results are packaged into a file named gather_info_[HOSTNAME]_[DATE]-[TIME].tar.gz."
	echo
	echo "  Supported operating systems:"
	echo "      RHEL 6, 7, 8 and 9"
	echo "      CentOS 6, 7 and 8"
	echo
	exit "${rc}"
}

#####
# Run command and catch/output errors to the log.
# Parameters:
#   $1 - Command to run
#   $2 - (optional) Additional command arguments
#####
run_command() {
	local command="$1"
	local args="$2"
	( bash -c "set -o pipefail && ${command} ${args}" ) >> "${GLOBAL_LOG_FILE}" 2>&1 & wait "$!"
	if [[ "$?" -gt 0 ]]; then
		warning_flag=1
		return 1
	fi
}

#####
# Check OS and version.
# Parameters:
#   None
#####
check_os() {
	if [[ -r "/etc/redhat-release" ]]; then
		local os_name
		os_full="$(cat /etc/redhat-release)"
		os_version="$(echo "${os_full}" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)"
		if [[ -z "${os_version}" ]]; then
			echo -e "\n[ERROR]: Unable to detect operating system."
			rc=1
			show_usage
		fi

		# split out checks for rhel 6-9 & centos 6-8
		if [[ ! ( "$(echo "${os_full}" | grep -oi "red hat enterprise linux" | wc -l)" -gt 0 && "${os_version}" -ge 6 && "${os_version}" -le 9 ) ]]; then
			if [[ ! ( "$(echo "${os_full}" | grep -oi "centos" | wc -l)" -gt 0 && "${os_version}" -ge 6 && "${os_version}" -le 8 ) ]]; then
				echo -e "\n[ERROR]: Operating system not supported."
				rc=1
				show_usage
			fi
		fi
	else
		echo -e "\n[ERROR]: Unable to access [/etc/redhat-release]."
		rc=1
		show_usage
	fi
}

#####
# Create directory if it doesn't exist.
# Parameters:
#   $1 - Directory to create
#####
create_dir() {
	local dir_name="${1%/}/"
	if [[ ! -d "${dir_name}" ]]; then
		echo "[INFO]: Creating destination directory [${dir_name}]." >> "${GLOBAL_LOG_FILE}"
		run_command "mkdir -p ${dir_name}" || echo "[WARN]: Copy failed. Unable to create directory [${dir_name}]." >> "${GLOBAL_LOG_FILE}"
	fi
}

#####
# Copy directory to output directory.
# Parameters:
#   $1 - Source directory
#####
copy_dir() {
	local src_dir="${1%/}/"
	local dst_dir="${GLOBAL_OUTPUT_DIR}${src_dir}"
	if [[ -d "${src_dir}" ]]; then
		echo "[INFO]: Copying directory [${src_dir}] to [${dst_dir}]." >> "${GLOBAL_LOG_FILE}"
		create_dir "${dst_dir}"
		if [[ -d "${dst_dir}" ]]; then
			run_command "cp -rp ${src_dir}* ${dst_dir}" || echo "[WARN]: Unable to copy directory [${src_dir}] to [${dst_dir}]." >> "${GLOBAL_LOG_FILE}"
		fi
	else
		echo "[WARN]: Unable to copy [${src_dir}]. Directory not found." >> "${GLOBAL_LOG_FILE}"
		warning_flag=1
	fi
}

#####
# Copy file to output directory.
# Parameters:
#   $1 - Source file
#####
copy_file() {
	local src_file="$1"
	local dst_file="${GLOBAL_OUTPUT_DIR}${src_file}"
	local dst_dir=$(dirname "${dst_file}")
	if [[ -r "${src_file}" ]]; then
		echo "[INFO]: Copying file [${src_file}] to [${dst_file}]." >> "${GLOBAL_LOG_FILE}"
		create_dir "${dst_dir}"
		if [[ -d "${dst_dir}" ]]; then
			run_command "cp -p ${src_file} ${dst_file}" || echo "[WARN]: Unable to copy file [${src_file}] to [${dst_file}]." >> "${GLOBAL_LOG_FILE}"
		fi
	else
		echo "[WARN]: Unable to copy [${src_file}]. File not found." >> "${GLOBAL_LOG_FILE}"
		warning_flag=1
	fi
}

#####
# Copy command output to output directory.
# Parameters:
#   None
#####
copy_commands() {
	local dst_dir="${GLOBAL_OUTPUT_DIR}/commands"
	echo "[INFO]: Copying output of commands to [${dst_dir}/]." >> "${GLOBAL_LOG_FILE}"
	create_dir "${dst_dir}"
	if [[ -d "${dst_dir}" ]]; then
		local command command_exists dst_file
		for command in "${commands[@]}"; do
			command_exists=$(type -p ${command})
			dst_file="${dst_dir}/${command// /_}.txt"
			if [[ -z "${command_exists}" ]]; then
				echo "[WARN]: Unable to copy output of [${command}]. Command not found." >> "${GLOBAL_LOG_FILE}"
				warning_flag=1
			else
				echo "[INFO]: Copying output of command [${command}] to [${dst_file}]." >> "${GLOBAL_LOG_FILE}"
				run_command "${command}" "2>&1 >${dst_file} | tee -a ${dst_file}" || echo "[WARN]: Command [${command}] returned with a non-zero exit code." >> "${GLOBAL_LOG_FILE}"
			fi
		done
	fi
}

#####
# Create final tarball and clean up output directory.
# Parameters:
#   None
#####
tar_files() {
	echo "[INFO]: Creating tarball [${GLOBAL_TAR_FILE}]." >> "${GLOBAL_LOG_FILE}"
	run_command "tar -zcf ${GLOBAL_TAR_FILE} -C ${GLOBAL_SCRIPT_DIR} ./${GLOBAL_OUTPUT_NAME} ./${GLOBAL_LOG_NAME} ${GLOBAL_SCRIPT_NAME}" || error_flag=1
	if [[ "${error_flag}" -gt 0 ]]; then
		echo "[ERROR]: Unable to create tarball [${GLOBAL_TAR_FILE}]. Please manually tar output directory [${GLOBAL_OUTPUT_DIR}]." >> "${GLOBAL_LOG_FILE}"
	else
		echo -e "Successfully created tarball [${GLOBAL_TAR_FILE}].\n"
		echo "[INFO]: Successfully created tarball [${GLOBAL_TAR_FILE}]." >> "${GLOBAL_LOG_FILE}"
		echo "[INFO]: Cleaning up output directory [${GLOBAL_OUTPUT_DIR}]." >> "${GLOBAL_LOG_FILE}"
		run_command "rm -rf ${GLOBAL_OUTPUT_DIR}" || error_flag=1
		if [[ "${error_flag}" -gt 0 ]]; then
			echo "[ERROR]: Unable to clean up output directory [${GLOBAL_OUTPUT_DIR}]. This may need to be cleaned up manually." >> "${GLOBAL_LOG_FILE}"
		fi
	fi
}

#####
# Gather system info.
# Parameters:
#   None
#####
gather_info() {
	# copy /proc files
	if [[ -d "/proc" ]]; then
		for proc_file in ${proc_files}; do
			copy_file "/proc/${proc_file}"
		done
	else
		echo "[WARN]: Unable to gather info from [/proc/]. Directory not found." >> "${GLOBAL_LOG_FILE}"
		warning_flag=1
	fi

	# copy /etc files and directories
	if [[ -d "/etc" ]]; then
		for etc_file in ${etc_files}; do
			copy_file "/etc/${etc_file}"
		done
		for etc_dir in ${etc_dirs}; do
			copy_dir "/etc/${etc_dir}"
		done
	else
		echo "[WARN]: Unable to gather info from [/etc/]. Directory not found." >> "${GLOBAL_LOG_FILE}"
		warning_flag=1
	fi

	# copy other files
	for other_files_item in ${other_files}; do
		other_files_dir=$(echo ${other_files_item} | awk -F\: '{ print $1 }')
		other_files_names=$(echo ${other_files_item} | awk -F\: '{ print $2 }' | sed "s;,; ;g")
		if [[ -d "${other_files_dir}" ]]; then
			for other_files_name in ${other_files_names}; do
				copy_file "${other_files_dir}/${other_files_name}"
			done
		else
			echo "[WARN]: Unable to gather info from [${other_files_dir}/]. Directory not found." >> "${GLOBAL_LOG_FILE}"
			warning_flag=1
		fi
	done

	# copy tuned profiles and config
	if [[ "${os_version}" -eq 6 ]]; then
		copy_dir "/etc/tune-profiles"
	else
		copy_dir "/usr/lib/tuned"
		copy_dir "/etc/tuned"
	fi
	
	copy_commands
	tar_files

	if [[ ${warning_flag} -eq 1 || ${error_flag} -eq 1 ]]; then
		echo "[INFO]: ----------" >> "${GLOBAL_LOG_FILE}"
		if [[ ${warning_flag} -eq 1 ]]; then
			echo "[INFO]: WARNINGs found. Please see above for more details." >> "${GLOBAL_LOG_FILE}"
		fi
		if [[ ${error_flag} -eq 1 ]]; then
			echo -e "[INFO]: ERRORs found. Please see above for more details." >> "${GLOBAL_LOG_FILE}"
			echo -e "Errors found. Please see [${GLOBAL_LOG_FILE}] for more details.\n"
		fi
	fi
}

#####
# Initialize the program and validate the environment.
# Parameters:
#   None
#####
initialize() {
	check_os
	if [[ -f "${GLOBAL_TAR_FILE}" ]]; then
		echo -e "\n[ERROR]: Tarball [${GLOBAL_TAR_FILE}] already exists. Exiting...\n"
		exit 1
	fi
	if [[ -f "${GLOBAL_LOG_FILE}" ]]; then
		echo -e "\n[ERROR]: Log file [${GLOBAL_LOG_FILE}] already exists. Exiting...\n"
		exit 1
	fi
	if [[ -f "${GLOBAL_OUTPUT_DIR}" ]]; then
		echo -e "\n[ERROR]: Output directory [${GLOBAL_OUTPUT_DIR}] already exists. Exiting...\n"
		exit 1
	fi
	echo "[INFO]: Script Name:    ${GLOBAL_SCRIPT_NAME}" > "${GLOBAL_LOG_FILE}"
	echo "[INFO]: Script Version: ${GLOBAL_SCRIPT_VERSION}" >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: Script Build:   ${GLOBAL_SCRIPT_BUILD_ID}" >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: Copyright (c) 2022-2023 SAS Institute Inc." >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: Unpublished - All Rights Reserved." >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: ----------" >> "${GLOBAL_LOG_FILE}"
	if [[ "${GLOBAL_FHOST}" == "hostname: Name or service not known" ]]; then
		echo "[INFO]: Hostname:       ${GLOBAL_SHOST}" >> "${GLOBAL_LOG_FILE}"
	else
		echo "[INFO]: Hostname:       ${GLOBAL_FHOST}" >> "${GLOBAL_LOG_FILE}"
	fi
	echo "[INFO]: Date:           $(date)" >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: Run ID:         ${GLOBAL_DATETIME}" >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: OS Version:     ${os_full}" >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: Script Dir:     ${GLOBAL_SCRIPT_DIR}/" >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: Output Dir:     ${GLOBAL_OUTPUT_DIR}/" >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: ----------" >> "${GLOBAL_LOG_FILE}"
	echo "[INFO]: Gathering system information..." >> "${GLOBAL_LOG_FILE}"
	echo -e "\nGathering system information...\n"
	create_dir "${GLOBAL_OUTPUT_DIR}"
	if [[ ! -d "${GLOBAL_OUTPUT_DIR}" ]]; then
		echo ""
		echo "[ERROR]: Unable to create output directory [${GLOBAL_OUTPUT_DIR}]. Exiting...\n" | tee -a "${GLOBAL_LOG_FILE}"
		exit 1
	fi
}

# ====================================================================
# MAIN SECTION
# ====================================================================
if [[ $# -gt 1 ]]; then
	echo -e "\n[ERROR]: Too many parameters given. Exiting..."
	rc=1
	show_usage
fi
if [[ $# -eq 0 ]]; then
	# Verify that this script is being ran as root
	if [[ $EUID -ne 0 ]]; then
		echo -e "\n[ERROR]: This script must be run as root."
		rc=1
		show_usage
	fi
	initialize
	gather_info
else
	case "$1" in
		-h|--h|-help|--help) show_usage ;;
		-v|--v|-version|--version) show_version ;;
		*) echo -e "\n[ERROR]: Invalid parameter. Exiting...\n"; exit 1 ;;
	esac
fi
exit "${error_flag}"
