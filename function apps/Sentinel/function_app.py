import subprocess
import os
import logging

def main(req: func.HttpRequest) -> func.HttpResponse:
    script_path = "C:\\Export\\zendesk\\ZendeskTicketData2Days.ps1"
    expected_csv = "C:\\Export\\zendesk\\zendesk_ticket_export.csv"

    try:
        result = subprocess.run(
            ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", script_path],
            capture_output=True,
            text=True,
            shell=True
        )

        logging.info(f"STDOUT: {result.stdout}")
        logging.error(f"STDERR: {result.stderr}")

        if result.returncode != 0:
            return func.HttpResponse("PowerShell script failed.", status_code=500)

        if not os.path.exists(expected_csv):
            return func.HttpResponse("CSV not created.", status_code=500)

        return func.HttpResponse("Script ran successfully and CSV created.", status_code=200)

    except Exception as e:
        logging.exception("Unhandled error")
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
