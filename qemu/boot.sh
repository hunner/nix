qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -smp 4 \
  -cpu host \
  -drive file=/home/hunner/Downloads/latest-nixos-minimal-x86_64-linux.iso,media=cdrom \
  -drive file=disk1.qcow2,format=qcow2,if=virtio \
  -drive file=disk2.qcow2,format=qcow2,if=virtio \
  -boot menu=on,splash-time=5000 \
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
  -display gtk

  #-drive file=/home/hunner/Downloads/nixos-minimal-23.05.2664.9034b46dc4c7-x86_64-linux.iso,media=cdrom \
