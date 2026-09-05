echo "🔧 Mounting volume..."

# Create mount point
mkdir -p /mnt/data

# Format the volume (only if not formatted)
if ! blkid /dev/sda | grep -q "TYPE="; then
    echo "📦 Formatting volume..."
    mkfs.ext4 -F /dev/sda
else
    echo "✅ Volume already formatted"
fi

# Mount the volume
echo "🔗 Mounting volume..."
mount /dev/sda /mnt/data

# Verify mount
echo "📊 Checking mount..."
df -h /mnt/data

# Create a test file
echo "✅ Volume mounted successfully at $(date)" > /mnt/data/README.txt
echo "📄 Test file created: /mnt/data/README.txt"

# Show volume info
echo ""
echo "📊 Volume Information:"
ls -la /mnt/data/

# 1. Update fstab with the correct volume name
sed -i 's/data-volume-aze/data-volume-b6m/g' /etc/fstab

# 2. Verify the fix
cat /etc/fstab | grep data-volume

# 3. Reload systemd and test
systemctl daemon-reload
mount -a

# 4. Verify it's still mounted
df -h /mnt/data