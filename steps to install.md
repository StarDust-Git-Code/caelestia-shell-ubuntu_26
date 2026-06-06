# Steps to Install Caelestia Shell on Ubuntu 26.04

Follow these steps to build and install the Caelestia shell, Hyprland compositor, and all necessary dependencies from source.

## Step 1: Open Terminal
Open your default terminal application on Ubuntu (usually `Ctrl + Alt + T`).

## Step 2: Clone the Repository
You must clone the repository with all of its submodules, otherwise the installation will fail. Run the following command:

```bash
git clone --recursive https://github.com/caelestia-dots/shell.git
```

## Step 3: Enter the Directory
Navigate into the newly cloned repository:

```bash
cd shell
```

## Step 4: Run the Installer
Make the installer script executable and run it. **Do not run this as root**; the script will ask for your password when it needs `sudo` privileges.

```bash
chmod +x install-ubuntu.sh
./install-ubuntu.sh
```

## Step 5: Wait for Compilation
The script will now download and compile everything from source. This process will take **30 to 60 minutes**, depending on your computer's performance and internet speed. 

## Step 6: Log Out
Once the script finishes successfully, log out of your current Ubuntu session.

## Step 7: Select the New Session
At the login screen:
1. Click on your username.
2. Look for the **gear icon** (usually in the bottom right corner).
3. Click the gear icon and select **"Caelestia (Hyprland)"**.
4. Enter your password and log in.

Welcome to your new shell!

---

### Uninstallation
If you ever want to remove the shell and its source-built dependencies:
```bash
cd shell
./uninstall-ubuntu.sh
```
