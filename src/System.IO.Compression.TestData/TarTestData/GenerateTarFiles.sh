#/bin/bash

# Script that generates tar files for the contents of all the folders located inside the folder
# runtime-assets/src/System.IO.Compression.TestData/TarTestData/unarchived/
# and saves them in additional new folders under 'TarTestData', one folder for each compression method.
# The user executing this script must be part of the sudo group.

# The tests should verify these preselected permission and ownership values
TarUser="dotnet"
TarGroup="devdiv"
TarUserId=7913
TarGroupId=3579

# These DevMajor and DevMinor numbers have no meaning, but those are the
# numbers that the tests should look for when reading device files.
CharDevMajor=49
CharDevMinor=86
BlockDevMajor=71
BlockDevMinor=53

FormatsArray=( "v7" "ustar" "pax" "oldgnu" "gnu")

GEAPAXOptions="--pax-option=globexthdr.MyGlobalExtendedAttribute=hello"

### FUNCTIONS ###

function Echo()
{
    Color=$1
    Message=$2
    OriginalColor="\e[0m"

    echo -e "$Color$Message$OriginalColor"
}

function EchoError()
{
    red="\e[31m"
    Echo $red "$1"
}

function EchoWarning()
{
    yellow="\e[33m"
    Echo $yellow "$1"
}

function EchoSuccess()
{
    green="\e[32m"
    Echo $green "$1"
}

function EchoInfo()
{
    cyan="\e[36m"
    Echo $cyan "$1"
}

function CheckLastErrorOrExit()
{
    message=$1

    if [ $? -ne 0 ]; then
        EchoError "Failure: $message"
        EchoError "Script failed to finish."
        exit 1
    else
        EchoSuccess "Success: $message"
    fi
}

function ConfirmDirExists()
{
    Dir=$1

    if [ ! -d $Dir ]; then
        EchoError "Directory did not exist: $Dir"
        exit 1
    fi
}

function DeleteAndRecreateDir()
{
    Dir=$1

    if [ -d $Dir ]; then
        EchoWarning "Deleting folder: $Dir"
        sudo rm -r $Dir
    fi

    EchoWarning "Creating folder: $Dir"
    mkdir $Dir

    ConfirmDirExists $Dir
}

function ExecuteTar()
{
    FullPathFolderToArchive=$1
    Arguments=$2
    FileName=$3
    Format=$4
    WithGlobalExtendedAttributes=$5

    EchoSuccess "----------------------------------------------"

    GEAArgument=""
    if [ $Format = "pax" ] && [ $WithGlobalExtendedAttributes = 1 ]; then
        EchoWarning "Creating extra pax file with extended attributes: $FileName"
        GEAArgument="$GEAPAXOptions"
    fi

    # IMPORTANT: This will ensure we archive entries that have relative paths to this folder
    EchoInfo "cd $FullPathFolderToArchive"
    cd $FullPathFolderToArchive

    TarCommand="tar $Arguments $FileName * --format=$Format $GEAArgument"
    EchoInfo "$TarCommand"

    # Execute the command as the user that owns the files
    # to archive, otherwise tar fails to pack them
    sudo $TarCommand

    if [ $? -ne 0 ]; then
        EchoError "Tar command failed!"
        if [ -f $FileName ]; then
            EchoError "Deleting malformed file: $FileName"
            sudo rm $FileName
        fi
    else
        EchoSuccess "Tar archive created successfully: $FileName"
    fi

    EchoSuccess "----------------------------------------------"
}

function GenerateArchive()
{
    DirsRoot=$1
    TargetDir=$2
    Arguments=$3
    Extension=$4

    UnarchivedDir="$DirsRoot/unarchived"
    FoldersToArchiveArray=($(ls $UnarchivedDir))

    for Format in "${FormatsArray[@]}"; do

        OutputDir="$TargetDir/$Format"
        DeleteAndRecreateDir $OutputDir

        for FolderToArchive in "${FoldersToArchiveArray[@]}"; do

            FullPathFolderToArchive="$UnarchivedDir/$FolderToArchive/"
            FileName="$OutputDir/$FolderToArchive$Extension"

            ExecuteTar "$FullPathFolderToArchive" "$Arguments" "$FileName" "$Format" 0

            # Special case: Generate an extra file but with a global extended attributes entry
            if [ $Format = "pax" ]; then
                GEAFileName="$OutputDir/${FolderToArchive}_gea_${Extension}"
                ExecuteTar "$FullPathFolderToArchive" "$Arguments" "$GEAFileName" "pax" 1
            fi

        done
    done

    # Tar was executed elevated, need to ensure the
    # generated archives are readable by current user
    ResetOwnership $TargetDir
}

function GenerateTarArchives()
{
    DirsRoot=$1
    TargetDir=$2
    CompressionMethod=$3

    if [ $CompressionMethod = "tar" ]; then
        GenerateArchive $DirsRoot $TargetDir "cvf" ".tar"

    elif [ $CompressionMethod = "targz" ]; then
        GenerateArchive $DirsRoot $TargetDir "cvzf" ".tar.gz"

    else
        EchoError "Unsupported compression method: $CompressionMethod"
        exit 1
    fi
}

function GenerateCompressionMethodDir()
{
    DirsRoot=$1
    CompressionMethod=$2

    TargetDir="$DirsRoot/$CompressionMethod"
    DeleteAndRecreateDir $TargetDir

    GenerateTarArchives "$DirsRoot" "$TargetDir" "$CompressionMethod"
}

function GenerateCompressionMethodDirs()
{
    DirsRoot=$1

    CompressionMethodsArray=( "tar" "targz" )

    for CompressionMethod in "${CompressionMethodsArray[@]}"; do
        GenerateCompressionMethodDir "$DirsRoot" "$CompressionMethod"
    done
}

function ConfirmUserAndGroupExist()
{
    EchoWarning "Checking if user '$TarUser' and group '$TarGroup' exist..."

    if [ $(getent group $TarGroup) ]; then
        EchoSuccess "Group '$TarGroup' exists. No action taken."

    else
        EchoWarning "Group '$TarGroup' does not exist. Adding it."
        sudo groupadd $TarGroup
        EchoWarning "Changing id of '$TarGroup' to $TarGroupId"
        sudo groupmod -g $TarGroupId $TarGroup
    fi

    if id $TarUser &>/dev/null; then
        EchoSuccess "User '$TarUser' exists. No action taken."

    else
        EchoWarning "User '$TarUser' does not exist. Adding it."
        sudo useradd $TarUser
        EchoWarning "Changing id of '$TarUser' to $TarUserId"
        sudo usermod -u $TarUserId $TarUser
        EchoWarning "Adding new '$TarUser' user to new '$TarGroup' group."
        sudo usermod -a -G $TarGroup $TarUser
        EchoWarning "Setting password for new '$TarUser' user."
        sudo passwd $TarUser
    fi
}

function ResetOwnership()
{
    Folder=$1

    CurrentUser=$(id -u)
    CurrentGroup=$(id -g)

    sudo chown -R $CurrentUser:$CurrentGroup "$Folder"
    CheckLastErrorOrExit "Chown $CurrentUser:$CurrentGroup $Folder"
}

function ChangeUnarchivedOwnership()
{
    DirsRoot=$1

    CurrentUser=$(id -u)
    CurrentGroup=$(id -g)
    UnarchivedDir=$DirsRoot/unarchived
    UnarchivedDirContents=$UnarchivedDir/*
    UnarchivedChildrenArray=($(ls $UnarchivedDir))

    # First, we recursively change ownership of all files and folders
    EchoWarning "Changing ownership of contents of 'unarchived' folder to '$TarUser:$TarGroup'."
    sudo chown -R $TarUser:$TarGroup $UnarchivedDirContents
    CheckLastErrorOrExit "Chown $TarUser:$TarGroup $UnarchivedDirContents"

    # Second, we revert the ownership of the parent folders (no recursion).
    # This is so we can later 'cd' into them. This is a requirement for the 'tar' command
    # so that it archives entries relative to that folder.
    for UnarchivedChildDir in "${UnarchivedChildrenArray[@]}"; do
        EchoWarning "Preserving ownership of child folder: $UnarchivedChildDir"
        sudo chown $CurrentUser:$CurrentGroup $UnarchivedDir/$UnarchivedChildDir
        CheckLastErrorOrExit "Chown $CurrentUser:$CurrentGroup $UnarchivedChildDir"
    done
}

function ResetUnarchivedOwnership()
{
    DirsRoot=$1

    ResetOwnership "$DirsRoot/unarchived"
}

function ChangeUnarchivedMode()
{
    DirsRoot=$1

    EchoWarning "Setting 744 (rwx,r,r) permissions to contents of 'unarchived' folder."

    UnarchivedDirContents=$DirsRoot/unarchived/*

    # 744
    sudo chmod -R a=r $UnarchivedDirContents
    CheckLastErrorOrExit "Chmod a=r $UnarchivedDirContents"

    sudo chmod -R u+wx $UnarchivedDirContents
    CheckLastErrorOrExit "Chmod u+wx $UnarchivedDirContents"

    sudo chmod -R g-wx $UnarchivedDirContents
    CheckLastErrorOrExit "Chmod g-wx $UnarchivedDirContents"

    sudo chmod -R o-wx $UnarchivedDirContents
    CheckLastErrorOrExit "Chmod o-wx $UnarchivedDirContents"
}

# Character device, block device and fifo file (named pipe).
function CreateSpecialFiles()
{
    DirsRoot=$1

    DevicesDir=$DirsRoot/unarchived/specialfiles
    CharacterDevice=$DevicesDir/chardev
    BlockDevice=$DevicesDir/blockdev
    FifoFile=$DevicesDir/fifofile

    currentUser=$(id -u)
    currentGroup=$(id -g)

    if [ -d $DevicesDir ]; then
        EchoSuccess "Devices folder exists. No action taken."
    else
        # Empty directories can't get added to git
        EchoWarning "Devices folder does not exist. Creating it: $DevicesDir"
        mkdir $DevicesDir
    fi

    if [ -c $CharacterDevice ]; then
        EchoSuccess "Character device exists. No action taken."
    else
        EchoWarning "Character device does not exist. Creating it: $CharacterDevice"
        sudo mknod $CharacterDevice c $CharDevMajor $CharDevMinor
        CheckLastErrorOrExit "Creating character device $CharacterDevice"
        sudo chown $currentUser:$currentGroup $CharacterDevice
        CheckLastErrorOrExit "Chown $currentUser:$currentGroup $CharacterDevice"
    fi

    if [ -b $BlockDevice ]; then
        EchoSuccess "Block device exists. No action taken."
    else
        EchoWarning "Block device does not exist. Creating it: $BlockDevice"
        sudo mknod $BlockDevice b $BlockDevMajor $BlockDevMinor
        CheckLastErrorOrExit "Creating block device $BlockDevice"
        sudo chown $currentUser:$currentGroup $BlockDevice
        CheckLastErrorOrExit "Chown $currentUser:$currentGroup $BlockDevice"
    fi

    if [ -p $FifoFile ]; then
        EchoSuccess "Fifo file exists. No action taken."
    else
        EchoWarning "Fifo file does not exist. Creating it: $FifoFile"
        sudo mknod $FifoFile p
        CheckLastErrorOrExit "Creating fifo file $FifoFile"
        sudo chown $currentUser:$currentGroup $FifoFile
        CheckLastErrorOrExit "Chown $currentUser:$currentGroup $FifoFile"
    fi
}

function BeginGeneration()
{
    DirsRoot=$1
    ConfirmUserAndGroupExist
    ConfirmDirExists $DirsRoot
    ChangeUnarchivedMode $DirsRoot
    ChangeUnarchivedOwnership $DirsRoot
    CreateSpecialFiles $DirsRoot
    GenerateCompressionMethodDirs $DirsRoot
    ResetUnarchivedOwnership $DirsRoot
    EchoSuccess "Script finished successfully!"
}

### SCRIPT EXECUTION ###

# IMPORTANT: Do not move the script to another location.
# It assumes it's located inside 'TarTestdata', on the same level as 'unarchived'.
ScriptPath=$(readlink -f $0)
DirsRoot=$(dirname $ScriptPath)

BeginGeneration $DirsRoot
