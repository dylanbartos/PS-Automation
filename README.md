# QuickBooks Database Service Monitor
Designed to resolve the error QuickBooks DataBase Manager Services encounter when they are unable to start while the DNS Server service is running. Automatically exits if the QB or DNS service is not installed and/or not in stopped state. Will attempt to stop DNS service, then start QB service and DNS service. Performs final check to verify services are running. Designed for use in ConnectWise Automate, but could easily be modified for use in Task Scheduler and/or another RMM.

# PC Deployment
Coming soon...
An XML configurable script to automate pc deployments including windows updates, software installation, user account creation, and more!
