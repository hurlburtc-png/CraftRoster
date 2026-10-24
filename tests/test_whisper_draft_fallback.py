"""Whisper fallback must retain drafts when the chat UI cannot open them.

Mock-only regression coverage across supported Lua runtimes and client profiles.
"""
import unittest
from test_work_orders import fresh

SETUP = """
local composer=addon.WhisperComposer
composer.frame=CreateFrame('Frame')
composer.frame.Status=CreateFrame('FontString')
composer.frame.Edit=CreateFrame('EditBox')
composer.frame.Send=CreateFrame('Button')
composer.frame.Edit:SetText('Please craft the item')
composer.target='Crafter-Realm'
composer.queue={'First message','Second message'}
SendChatMessage=nil
ChatFrame_SendTell=nil
ChatEdit_ChooseBoxForSend=nil
"""

CASES = {
    "missing_chat_api_keeps_queue_for_retry": """
        ChatFrame_OpenChat=nil
        assert(not composer:SendNext())
        assert(#composer.queue==2 and composer.queue[1]=='First message')
        assert(addon.Requests.whisperDrafts==nil)
        assert(composer.frame.Status:GetText():find('kept for retry',1,true))
        local opened
        ChatFrame_OpenChat=function(text) opened=text end
        assert(not composer:SendNext())
        assert(opened=='/w Crafter-Realm First message')
        assert(composer.queue==nil)
        assert(#addon.Requests.whisperDrafts==1)
        assert(addon.Requests.whisperDrafts[1]=='Second message')
    """,
    "chat_api_error_keeps_queue_for_retry": """
        ChatFrame_OpenChat=function() error('blocked chat frame') end
        assert(not composer:SendNext())
        assert(#composer.queue==2 and composer.queue[2]=='Second message')
        assert(addon.Requests.whisperDrafts==nil)
        ChatFrame_OpenChat=function(text) assert(text=='/w Crafter-Realm First message') end
        assert(not composer:SendNext())
        assert(composer.queue==nil)
        assert(#addon.Requests.whisperDrafts==1)
    """,
}

class WhisperDraftFallbackTests(unittest.TestCase):
    pass

for runtime in ('lua51', 'luajit21'):
    for profile in ('modern', 'legacy', 'minimal'):
        for name, code in CASES.items():
            def check(self, runtime=runtime, profile=profile, code=code):
                lua=fresh(runtime, profile)
                lua.execute(SETUP + code)
            setattr(WhisperDraftFallbackTests, f'test_{runtime}_{profile}_{name}', check)
