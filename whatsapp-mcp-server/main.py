import sys
import os
import subprocess
import time
import shutil
from typing import List, Dict, Any, Optional
from mcp.server.fastmcp import FastMCP
from whatsapp import MESSAGES_DB_PATH

BRIDGE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'whatsapp-bridge')
BRIDGE_BINARY = os.path.join(BRIDGE_DIR, 'whatsapp-bridge')
QR_DATA_PATH = "/tmp/wa_qr_data.txt"
QR_PNG_PATH = "/tmp/wa_qrcode.png"

bridge_configured = os.path.exists(MESSAGES_DB_PATH)

# Initialize FastMCP server
mcp = FastMCP("whatsapp")


if not bridge_configured:
    # --- SETUP MODE: only expose setup tool ---

    @mcp.tool()
    def setup_whatsapp() -> Dict[str, Any]:
        """Connect your WhatsApp account. This compiles the bridge, starts it, and generates a QR code for you to scan with your phone. Call this tool to begin setup.

        Returns:
            Status of setup and path to QR code image to scan
        """
        # Step 1: Check Go is installed
        if not shutil.which("go"):
            return {
                "success": False,
                "step": "prerequisites",
                "message": "Go is not installed. Install it from https://go.dev/dl/ and try again."
            }

        # Step 2: Compile bridge if needed
        if not os.path.exists(BRIDGE_BINARY):
            try:
                result = subprocess.run(
                    ["go", "build", "-o", "whatsapp-bridge", "main.go"],
                    cwd=BRIDGE_DIR,
                    capture_output=True, text=True, timeout=120
                )
                if result.returncode != 0:
                    return {
                        "success": False,
                        "step": "compile",
                        "message": f"Failed to compile bridge: {result.stderr}"
                    }
            except subprocess.TimeoutExpired:
                return {
                    "success": False,
                    "step": "compile",
                    "message": "Compilation timed out after 120 seconds."
                }

        # Step 3: Clean old QR data
        for f in [QR_DATA_PATH, QR_PNG_PATH]:
            if os.path.exists(f):
                os.remove(f)

        # Step 4: Start bridge in background
        bridge_process = subprocess.Popen(
            [BRIDGE_BINARY],
            cwd=BRIDGE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        # Step 5: Wait for QR code data to be written
        qr_found = False
        for _ in range(60):  # wait up to 60 seconds
            time.sleep(1)
            if os.path.exists(QR_DATA_PATH):
                qr_found = True
                break
            # Check if bridge died
            if bridge_process.poll() is not None:
                output = bridge_process.stdout.read() if bridge_process.stdout else ""
                # If it connected without QR (existing session), check for DB
                if os.path.exists(MESSAGES_DB_PATH):
                    return {
                        "success": True,
                        "step": "complete",
                        "message": "WhatsApp bridge connected with existing session. Restart the MCP server to load all tools."
                    }
                return {
                    "success": False,
                    "step": "bridge_start",
                    "message": f"Bridge exited unexpectedly: {output[:500]}"
                }

        if not qr_found:
            bridge_process.terminate()
            return {
                "success": False,
                "step": "qr_wait",
                "message": "Timed out waiting for QR code. Check if another bridge instance is already running."
            }

        # Step 6: Generate QR code PNG
        qr_data = open(QR_DATA_PATH).read().strip()
        try:
            subprocess.run(
                [sys.executable, "-c",
                 f"import qrcode; qrcode.make('{qr_data}').save('{QR_PNG_PATH}')"],
                capture_output=True, timeout=10
            )
        except Exception:
            pass  # QR PNG is optional, user can still use terminal QR

        if os.path.exists(QR_PNG_PATH):
            return {
                "success": True,
                "step": "qr_ready",
                "message": f"QR code generated! Open this image and scan it with WhatsApp on your phone (Settings > Linked Devices > Link a Device). After scanning, restart the MCP server.",
                "qr_image_path": QR_PNG_PATH,
                "note": "The bridge is running in the background. After scanning the QR code, restart this MCP server to load all WhatsApp tools."
            }
        else:
            return {
                "success": True,
                "step": "qr_ready",
                "message": f"Bridge is running. QR code is displayed in the bridge terminal. Scan it with WhatsApp on your phone. After scanning, restart this MCP server.",
                "note": "If you can't see the terminal QR, install qrcode package: pip install qrcode"
            }

else:
    # --- NORMAL MODE: all WhatsApp tools ---

    from whatsapp import (
        search_contacts as whatsapp_search_contacts,
        list_messages as whatsapp_list_messages,
        list_chats as whatsapp_list_chats,
        get_chat as whatsapp_get_chat,
        get_direct_chat_by_contact as whatsapp_get_direct_chat_by_contact,
        get_contact_chats as whatsapp_get_contact_chats,
        get_last_interaction as whatsapp_get_last_interaction,
        get_message_context as whatsapp_get_message_context,
        send_message as whatsapp_send_message,
        send_file as whatsapp_send_file,
        send_audio_message as whatsapp_audio_voice_message,
        download_media as whatsapp_download_media
    )

    @mcp.tool()
    def search_contacts(query: str) -> List[Dict[str, Any]]:
        """Search WhatsApp contacts by name or phone number.

        Args:
            query: Search term to match against contact names or phone numbers
        """
        contacts = whatsapp_search_contacts(query)
        return contacts

    @mcp.tool()
    def list_messages(
        after: Optional[str] = None,
        before: Optional[str] = None,
        sender_phone_number: Optional[str] = None,
        chat_jid: Optional[str] = None,
        query: Optional[str] = None,
        limit: int = 20,
        page: int = 0,
        include_context: bool = True,
        context_before: int = 1,
        context_after: int = 1,
        media_type: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """Get WhatsApp messages matching specified criteria with optional context.

        Args:
            after: Optional ISO-8601 formatted string to only return messages after this date
            before: Optional ISO-8601 formatted string to only return messages before this date
            sender_phone_number: Optional phone number to filter messages by sender
            chat_jid: Optional chat JID to filter messages by chat
            query: Optional search term to filter messages by content
            limit: Maximum number of messages to return (default 20)
            page: Page number for pagination (default 0)
            include_context: Whether to include messages before and after matches (default True)
            context_before: Number of messages to include before each match (default 1)
            context_after: Number of messages to include after each match (default 1)
            media_type: Optional filter by media type ("image", "video", "audio", "document")
        """
        messages = whatsapp_list_messages(
            after=after,
            before=before,
            sender_phone_number=sender_phone_number,
            chat_jid=chat_jid,
            query=query,
            limit=limit,
            page=page,
            include_context=include_context,
            context_before=context_before,
            context_after=context_after,
            media_type=media_type
        )
        return messages

    @mcp.tool()
    def list_chats(
        query: Optional[str] = None,
        limit: int = 20,
        page: int = 0,
        include_last_message: bool = True,
        sort_by: str = "last_active"
    ) -> List[Dict[str, Any]]:
        """Get WhatsApp chats matching specified criteria.

        Args:
            query: Optional search term to filter chats by name or JID
            limit: Maximum number of chats to return (default 20)
            page: Page number for pagination (default 0)
            include_last_message: Whether to include the last message in each chat (default True)
            sort_by: Field to sort results by, either "last_active" or "name" (default "last_active")
        """
        chats = whatsapp_list_chats(
            query=query,
            limit=limit,
            page=page,
            include_last_message=include_last_message,
            sort_by=sort_by
        )
        return chats

    @mcp.tool()
    def get_chat(chat_jid: str, include_last_message: bool = True) -> Dict[str, Any]:
        """Get WhatsApp chat metadata by JID.

        Args:
            chat_jid: The JID of the chat to retrieve
            include_last_message: Whether to include the last message (default True)
        """
        chat = whatsapp_get_chat(chat_jid, include_last_message)
        return chat

    @mcp.tool()
    def get_direct_chat_by_contact(sender_phone_number: str) -> Dict[str, Any]:
        """Get WhatsApp chat metadata by sender phone number.

        Args:
            sender_phone_number: The phone number to search for
        """
        chat = whatsapp_get_direct_chat_by_contact(sender_phone_number)
        return chat

    @mcp.tool()
    def get_contact_chats(jid: str, limit: int = 20, page: int = 0) -> List[Dict[str, Any]]:
        """Get all WhatsApp chats involving the contact.

        Args:
            jid: The contact's JID to search for
            limit: Maximum number of chats to return (default 20)
            page: Page number for pagination (default 0)
        """
        chats = whatsapp_get_contact_chats(jid, limit, page)
        return chats

    @mcp.tool()
    def get_last_interaction(jid: str) -> str:
        """Get most recent WhatsApp message involving the contact.

        Args:
            jid: The JID of the contact to search for
        """
        message = whatsapp_get_last_interaction(jid)
        return message

    @mcp.tool()
    def get_message_context(
        message_id: str,
        before: int = 5,
        after: int = 5
    ) -> Dict[str, Any]:
        """Get context around a specific WhatsApp message.

        Args:
            message_id: The ID of the message to get context for
            before: Number of messages to include before the target message (default 5)
            after: Number of messages to include after the target message (default 5)
        """
        context = whatsapp_get_message_context(message_id, before, after)
        return context

    @mcp.tool()
    def send_message(
        recipient: str,
        message: str
    ) -> Dict[str, Any]:
        """Send a WhatsApp message to a person or group. For group chats use the JID.

        Args:
            recipient: The recipient - either a phone number with country code but no + or other symbols,
                     or a JID (e.g., "123456789@s.whatsapp.net" or a group JID like "123456789@g.us")
            message: The message text to send

        Returns:
            A dictionary containing success status and a status message
        """
        if not recipient:
            return {
                "success": False,
                "message": "Recipient must be provided"
            }

        success, status_message = whatsapp_send_message(recipient, message)
        return {
            "success": success,
            "message": status_message
        }

    @mcp.tool()
    def send_file(recipient: str, media_path: str) -> Dict[str, Any]:
        """Send a file such as a picture, raw audio, video or document via WhatsApp to the specified recipient. For group messages use the JID.

        Args:
            recipient: The recipient - either a phone number with country code but no + or other symbols,
                     or a JID (e.g., "123456789@s.whatsapp.net" or a group JID like "123456789@g.us")
            media_path: The absolute path to the media file to send (image, video, document)

        Returns:
            A dictionary containing success status and a status message
        """
        success, status_message = whatsapp_send_file(recipient, media_path)
        return {
            "success": success,
            "message": status_message
        }

    @mcp.tool()
    def send_audio_message(recipient: str, media_path: str) -> Dict[str, Any]:
        """Send any audio file as a WhatsApp audio message to the specified recipient. For group messages use the JID. If it errors due to ffmpeg not being installed, use send_file instead.

        Args:
            recipient: The recipient - either a phone number with country code but no + or other symbols,
                     or a JID (e.g., "123456789@s.whatsapp.net" or a group JID like "123456789@g.us")
            media_path: The absolute path to the audio file to send (will be converted to Opus .ogg if it's not a .ogg file)

        Returns:
            A dictionary containing success status and a status message
        """
        success, status_message = whatsapp_audio_voice_message(recipient, media_path)
        return {
            "success": success,
            "message": status_message
        }

    @mcp.tool()
    def download_media(message_id: str, chat_jid: str) -> Dict[str, Any]:
        """Download media from a WhatsApp message and get the local file path.

        Args:
            message_id: The ID of the message containing the media
            chat_jid: The JID of the chat containing the message

        Returns:
            A dictionary containing success status, a status message, and the file path if successful
        """
        file_path = whatsapp_download_media(message_id, chat_jid)

        if file_path:
            return {
                "success": True,
                "message": "Media downloaded successfully",
                "file_path": file_path
            }
        else:
            return {
                "success": False,
                "message": "Failed to download media"
            }

if __name__ == "__main__":
    mcp.run(transport='stdio')
