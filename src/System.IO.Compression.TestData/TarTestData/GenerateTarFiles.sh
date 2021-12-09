#/bin/bash

# Script that generates tar files for the contents of all the folders located inside the folder
# runtime-assets/src/System.IO.Compression.TestData/TarTestData/unarchived/
# and saves them in additional new folders under 'TarTestData', one folder for each compression method.

### FUNCTIONS ###

function Echo()
{
    color=$1
    message=$2
    originalColor="\e[0m"

    echo -e "$color$message$originalColor"
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
        EchoWarning "Deleting directory: $Dir"
        rm -r $Dir
    fi

    EchoWarning "Creating directory: $Dir"
    mkdir $Dir

    ConfirmDirExists $Dir
}

function ExecuteTar()
{
    FullPathFolderToArchive=$1
    Arguments=$2
    Filename=$3
    Format=$4

    EchoSuccess "----------------------------------------------"

    # IMPORTANT: This will ensure we archive entries that have relative paths to this folder
    EchoInfo "cd $FullPathFolderToArchive"
    cd $FullPathFolderToArchive

    EchoInfo "tar $Arguments --format=$Format $FileName *"
    tar $Arguments $FileName * --format=$Format

    if [ $? -ne 0 ]; then
        EchoError "Failed!"
        EchoError "Deleting '$FileName'."
        rm $FileName
    else
        EchoSuccess "Success!"
    fi

    EchoSuccess "----------------------------------------------"
}

function GenerateFile()
{
    DirsRoot=$1
    TargetDir=$2
    Arguments=$3
    Extension=$4

    UnarchivedDir="$DirsRoot/unarchived"
    FoldersToArchiveArray=($(ls $UnarchivedDir))
    FormatsArray=( "v7" "ustar" "pax" "gnu" "oldgnu" )

    for Format in "${FormatsArray[@]}"; do

        OutputDir="$TargetDir/$Format"
        DeleteAndRecreateDir $OutputDir

        for FolderToArchive in "${FoldersToArchiveArray[@]}"; do

            FullPathFolderToArchive="$UnarchivedDir/$FolderToArchive/"
            FileName="$OutputDir/$FolderToArchive$Extension"

            ExecuteTar "$FullPathFolderToArchive" "$Arguments" "$FileName" "$Format"

        done
    done
}

function GenerateTarFiles()
{
    DirsRoot=$1
    TargetDir=$2
    CompressionMethod=$3

    if [ $CompressionMethod = "tar" ]; then
        GenerateFile $DirsRoot $TargetDir "cvf" ".tar"

    elif [ $CompressionMethod = "targz" ]; then
        GenerateFile $DirsRoot $TargetDir "cvzf" ".tar.gz"

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

    GenerateTarFiles "$DirsRoot" "$TargetDir" "$CompressionMethod"
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
    tarUser="dotnet"
    tarGroup="devdiv"

    EchoWarning "Checking if user '$tarUser' and group '$tarGroup' exist..."

    if [ $(getent group $tarGroup) ]; then
        EchoSuccess "Group '$tarGroup' exists. No action taken."

    else
        EchoWarning "Group '$tarGroup' does not exist. Adding it."
        sudo groupadd $tarGroup
    fi

    if id $tarUser &>/dev/null; then
        EchoSuccess "User '$tarUser' exists. No action taken."

    else
        EchoWarning "User '$tarUser' does not exist. Adding it."
        sudo useradd $tarUser
        EchoWarning "Adding new '$tarUser' user to new '$tarGroup' group."
        sudo usermod -a -G $tarGroup $tarUser
        EchoWarning "Setting password for new '$tarUser' user."
        sudo passwd $tarUser
    fi
}

function ChangeUnarchivedOwnership()
{
    DirsRoot=$1

    EchoWarning "Changing ownership of contents of 'unarchived' folder to 'dotnet:devdiv'."
    sudo chown -R dotnet:devdiv $DirsRoot/unarchived/*
}

function ResetUnarchivedOwnership()
{
    DirsRoot=$1
    currentUser=$(id -u)
    currentGroup=$(id -g)

    EchoWarning "Resetting ownership of contents of 'unarchived' folder to '$currentUser:$currentGroup'."
    sudo chown -R $currentUser:$currentGroup $DirsRoot/unarchived/*
}

function BeginGeneration()
{
    DirsRoot=$1
    ConfirmUserAndGroupExist
    ConfirmDirExists $DirsRoot
    ChangeUnarchivedOwnership $DirsRoot
    GenerateCompressionMethodDirs $DirsRoot
    ResetUnarchivedOwnership $DirsRoot

}

### SCRIPT EXECUTION ###

# IMPORTANT: Do not move the script to another location.
# It assumes it's located inside 'TarTestdata', on the same level as 'unarchived'.
ScriptPath=$(readlink -f $0)
DirsRoot=$(dirname $ScriptPath)

BeginGeneration $DirsRoot
