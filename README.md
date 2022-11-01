# Gather System Info

The Gather System Info tool is a Bash script that gathers and packages a select set of information about a RHEL or CentOS 6, 7 or 8 system.

Results are packaged into a tarball named `gather_info_[HOSTNAME]_[DATE]-[TIME].tar.gz`.

## Prerequisites

- RHEL or CentOS 6, 7 or 8
- Sudo or root
- Bash

## Installation

Use Git to clone the contents of the RHEL Gather System Info GitHub repo: https://github.com/sassoftware/rhel-gather-system-info.

## Getting Started

The Gather System Info tool must be run as root and can be executed on any RHEL or CentOS 6, 7 or 8. It is a standalone Bash script and does not require any SAS software.

## Usage

```bash
./gather_info.sh (parameter)
```
Optional parameters:
- `-h`, `--help`:       Show usage info
- `-v`, `--version`:    Show version info

## Information Collected

The information collected by this script is used by SAS to assist with troubleshooting and to confirm the environment meets SAS/Red Hat tuning guidelines.

- All tuned profiles
- /etc/udev/
- /etc/lvm/
- /etc/redhat-release
- /etc/fstab
- /etc/multipath.conf
- /etc/security/limits.conf
- /etc/security/access.conf
- /proc/cpuinfo
- /proc/meminfo
- /proc/diskstats
- /proc/cmdline
- /proc/interrupts
- /proc/partitions
- /boot/grub/menu.lst
- /var/log/dmesg
- ifconfig -a
- getconf PAGESIZE
- tuned-adm active
- mount
- multipath -ll
- powermt version
- powermt display options
- powermt display dev=all
- powermt display hba_mode
- vxdmpadm getsubpaths
- vxdisk list
- vxddladm list devices
- uname -a
- lvs -o name,vg_name,size,attr,lv_size,stripes,stripesize,lv_read_ahead
- pvs
- vgs
- df -hT
- lscpu
- blockdev -report
- dmidecode

## Contributing

We welcome your contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to submit contributions to this project.

## License

This project is licensed under the [Apache 2.0 License](LICENSE).

## Additional Resources

- SAS Note: https://support.sas.com/kb/57/825.html
