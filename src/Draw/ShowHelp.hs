module Draw.ShowHelp (drawShowHelp) where

import Prelude ()
import Prelude.Compat

import Brick
import Brick.Themes (themeDescriptions)
import Brick.Widgets.Border
import Brick.Widgets.Center (hCenter, centerLayer)
import Brick.Widgets.List (listSelectedFocusedAttr)
import Lens.Micro.Platform
import Data.List (intercalate, sort)
import Data.Maybe (isNothing)
import qualified Data.Map as M
import qualified Data.Text as T
import Data.Monoid ((<>))
import qualified Graphics.Vty as Vty
import GHC.Exts (sortWith, groupWith)
import Network.Mattermost.Version (mmApiVersion)

import Themes
import Types
import Types.KeyEvents (Binding(..), ppBinding, nonCharKeys, eventToBinding)
import Events.Keybindings
import Command
import Events.ShowHelp
import Events.ChannelScroll
import Events.ChannelSelect
import Events.UrlSelect
import Events.Main
import Events.MessageSelect
import Events.PostListOverlay
import Events.UserListOverlay
import State.Editing (editingKeybindings)
import Markdown (renderText)
import Options (mhVersion)
import HelpTopics (helpTopics)

drawShowHelp :: HelpTopic -> ChatState -> [Widget Name]
drawShowHelp topic st =
    [helpBox (helpTopicViewportName topic) $ helpTopicDraw topic st]

helpTopicDraw :: HelpTopic -> ChatState -> Widget Name
helpTopicDraw topic st =
    case helpTopicScreen topic of
        MainHelp -> mainHelp (configUserKeys (st^.csResources.crConfiguration))
        ScriptHelp -> scriptHelp
        ThemeHelp -> themeHelp
        KeybindingHelp -> keybindingHelp (configUserKeys (st^.csResources.crConfiguration))

mainHelp :: KeyConfig -> Widget Name
mainHelp kc = commandHelp
  where
    commandHelp = vBox $ [ padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ str mhVersion
                         , hCenter $ withDefAttr helpEmphAttr $ str mmApiVersion
                         , padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Help Topics"
                         , drawHelpTopics
                         , padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Commands"
                         , mkCommandHelpText $ sortWith commandName commandList
                         ] <>
                         (mkKeybindingHelp <$> keybindSections kc)

    mkCommandHelpText :: [Cmd] -> Widget Name
    mkCommandHelpText cs =
      let helpInfo = [ (info, desc)
                     | Cmd cmd desc args _ <- cs
                     , let argSpec = printArgSpec args
                           info = T.cons '/' cmd <> " " <> argSpec
                     ]
          commandNameWidth = 4 + (maximum $ T.length <$> fst <$> helpInfo)
      in hCenter $
         vBox [ (withDefAttr helpEmphAttr $ txt $ padTo commandNameWidth info) <+> renderText desc
              | (info, desc) <- helpInfo
              ]

drawHelpTopics :: Widget Name
drawHelpTopics =
    let allHelpTopics = drawTopic <$> helpTopics
        topicNameWidth = 4 + (maximum $ T.length <$> helpTopicName <$> helpTopics)
        drawTopic t = (withDefAttr helpEmphAttr $ txt (padTo topicNameWidth $ helpTopicName t)) <+>
                      txt (helpTopicDescription t)
    in (padBottom (Pad 1) $
        hCenter $ renderText "Learn more about these topics with `/help <topic>`:") <=>
       (hCenter $ vBox allHelpTopics)

scriptHelp :: Widget Name
scriptHelp = vBox
  [ padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Using Scripts"
  , padTop (Pad 1) $ hCenter $ hLimit 100 $ vBox scriptHelpText
  ]
  where scriptHelpText = map (padTop (Pad 1) . renderText . mconcat)
          [ [ "Matterhorn has a special feature that allows you to use "
             , "prewritten shell scripts to preprocess messages. "
             , "For example, this can allow you to run various filters over "
             , "your written text, do certain kinds of automated formatting, "
             , "or just automatically cowsay-ify a message.\n" ]
           , [ "These scripts can be any kind of executable file, "
             , "as long as the file lives in "
             , "*~/.config/matterhorn/scripts* (unless you've explicitly "
             , "moved your XDG configuration directory elsewhere). "
             , "Those executables are given no arguments "
             , "on the command line and are passed your typed message on "
             , "*stdin*; whatever they produce on *stdout* is sent "
             , "as a message. If the script exits successfully, then everything "
             , "that appeared on *stderr* is discarded; if it instead exits with "
             , "a failing exit code, your message is *not* sent, and you are "
             , "presented with whatever was printed on stderr as a "
             , "local error message.\n" ]
           , [ "To run a script, simply type\n" ]
           , [ "> *> /sh [script-name] [my-message]*\n" ]
           , [ "And the script named *[script-name]* will be invoked with "
             , "the text of *[my-message]*. If the script does not exist, "
             , "or if it exists but is not marked as executable, you'll be "
             , "presented with an appropriate error message.\n" ]
           , [ "For example, if you want to use a basic script to "
             , "automatically ROT13 your message, you can write a shell "
             , "script using the standard Unix *tr* utility, like this:\n" ]
           , [ "> *#!/bin/bash -e*\n"
             , "> *tr '[A-Za-z]' '[N-ZA-Mn-za-m]'*\n\n" ]
           , [ "Move this script to *~/.config/matterhorn/scripts/rot13* "
             , "and be sure it's executable with\n" ]
           , [ "> *$ chmod u+x ~/.config/matterhorn/scripts/rot13*\n\n" ]
           , [ "after which you can send ROT13 messages with the "
             , "Matterhorn command " ]
           , [ "> *> /sh rot13 Hello, world!*\n" ]
           ]

keybindingHelp :: KeyConfig -> Widget Name
keybindingHelp kc = vBox $
  [ padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Configurable Keybindings"
  , padTop (Pad 1) $ hCenter $ hLimit 100 $ vBox keybindingHelpText
  ] ++ map mkKeybindEventSectionHelp (keybindSections kc)
    ++
  [ padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Keybinding Syntax"
  , padTop (Pad 1) $ hCenter $ hLimit 100 $ vBox validKeys
  ]
  where keybindingHelpText = map (padTop (Pad 1) . renderText . mconcat)
          [ [ "Many of the keybindings used in Matterhorn can be "
            , "modified from within Matterhorn's **config.ini** file. "
            , "To do this, include a section called **[KEYBINDINGS]** "
            , "in your config file and use the event names listed below as "
            , "keys and the desired key sequence as values. "
            , "See the end of this page for documentation on the valid "
            , "syntax for key sequences.\n"
            ]
          , [ "For example, by default, the keybinding to move to the next "
            , "channel in the public channel list is **"
            , nextChanBinding
            , "**, and the corresponding "
            , "previous channel binding is **"
            , prevChanBinding
            , "**. You might want to remap these "
            , "to other keys: say, **C-j** and **C-k**. We can do this with the following "
            , "configuration snippet:\n"
            ]
          , [ "```ini\n"
            , "[KEYBINDINGS]\n"
            , "focus-next-channel = C-j\n"
            , "focus-prev-channel = C-k\n"
            , "```\n"
            ]
          , [ "You can remap a command to more than one key sequence, in which "
            , "case any one of the key sequences provided can be used to invoke "
            , "the relevant command. To do this, provide the desired bindings as "
            , "a comma-separated list. Additionally, some key combinations are "
            , "used in multiple modes (such as URL select or help viewing) and "
            , "therefore share the same name, such as **cancel** or **scroll-up**.\n"
            ]
          , [ "Additionally, some keys simply cannot be remapped, mostly in the "
            , "case of editing keybindings. If you feel that a particular key "
            , "event should be rebindable and isn't, then please feel free to "
            , "let us know by posting an issue in the Matterhorn issue tracker.\n"
            ]
          , [ "It is also possible to entirely unbind a key event by setting its "
            , "key to **unbound**, thus avoiding conflicts between default bindings "
            , "and new ones:\n"
            ]
          , [ "```ini\n"
            , "[KEYBINDINGS]\n"
            , "focus-next-channel = unbound\n"
            , "```\n"
            ]
          , [ "The rebindable key events, along with their **current** "
            , "values, are as follows:"
            ]
           ]
        nextChanBinding = ppBinding (getFirstDefaultBinding NextChannelEvent)
        prevChanBinding = ppBinding (getFirstDefaultBinding PrevChannelEvent)
        validKeys = map (padTop (Pad 1) . renderText . mconcat)
          [ [ "The syntax used for key sequences consists of zero or more "
            , "single-character modifier characters followed by a keystroke "
            , "all separated by dashes. The available modifier keys are "
            , "**S** for Shift, **C** for Ctrl, **A** for Alt, and **M** for "
            , "Meta. So, for example, **"
            , ppBinding (Binding [] (Vty.KFun 2))
            , "** is the F2 key pressed with no "
            , "modifier keys; **"
            , ppBinding (Binding [Vty.MCtrl] (Vty.KChar 'x'))
            , "** is Ctrl and X pressed together, "
            , "and **"
            , ppBinding (Binding [Vty.MShift, Vty.MCtrl] (Vty.KChar 'x'))
            , "** is Shift, Ctrl, and X all pressed together. "
            , "Although Matterhorn will pretty-print all key combinations "
            , "with specific capitalization, the parser is **not** case-sensitive "
            , "and will ignore any capitalization."
            ]
          , [ "Your terminal emulator might not recognize some particular "
            , "keypress combinations, or it might reserve certain combinations of "
            , "keys for some terminal-specific operation. Matterhorn does not have a "
            , "reliable way of testing this, so it is up to you to avoid setting "
            , "keybindings that your terminal emulator does not deliver to applications."
            ]
          , [ "Letter keys, number keys, and function keys are specified with "
            , "their obvious name, such as **x** for the X key, **8** for the 8 "
            , "key, and **f5** for the F5 key. Other valid keys include: "
            , T.intercalate ", " [ "**" <> key <> "**" | key <- nonCharKeys ]
            , "."
            ]
          ]

themeHelp :: Widget a
themeHelp = overrideAttr codeAttr helpEmphAttr $ vBox
  [ padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Using Themes"
  , padTop (Pad 1) $ hCenter $ renderText "Matterhorn provides these built-in color themes:"
  , padTop (Pad 1) $ vBox $ hCenter <$> withDefAttr helpEmphAttr <$>
                            txt <$> internalThemeName <$> internalThemes
  , padTop (Pad 1) $ hCenter $ hLimit 72 $ renderText $
        "These themes can be selected with the */theme* command. To automatically " <>
        "select a theme at startup, set the *theme* configuration file option to one " <>
        "of the themes listed above."
  , padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Customizing the Theme"
  , padTop (Pad 1) $ hCenter $ hLimit 72 $ renderText $
        "Theme customization is also supported. To customize the selected theme, " <>
        "create a theme customization file and set the `themeCustomizationFile` " <>
        "configuration option to the path to the customization file. If the path " <>
        "to the file is relative, Matterhorn will look for it in the same directory " <>
        "as the Matterhorn configuration file.\n" <>
        "  \n" <>
        "Theme customization files are INI-style files that can customize any " <>
        "foreground color, background color, or style of any aspect of the " <>
        "Matterhorn user interface. Here is an example:\n" <>
        "```\n" <>
        "[default]\n" <>
        "default.fg = blue\n" <>
        "default.bg = black\n" <>
        "\n" <>
        "[other]\n" <>
        attrNameToConfig codeAttr <> ".fg = magenta\n" <>
        attrNameToConfig codeAttr <> ".style = bold\n" <>
        attrNameToConfig clientEmphAttr <> ".fg = cyan\n" <>
        attrNameToConfig clientEmphAttr <> ".style = [bold, underline]\n" <>
        attrNameToConfig listSelectedFocusedAttr <> ".fg = brightGreen\n" <>
        "```\n" <>
        "In the example above, the theme's default foreground and background colors " <>
        "are both customized to *blue* and *black*, respectively. The *default* section " <>
        "contains only customizations for the *default* attribute. All other customizations " <>
        "go in the *other* section. We can also set the style for attributes; we can either " <>
        "set just one style (as with the bold setting above) or multiple styles at once " <>
        "(as in the bold/underline example).\n\n" <>
        "Available colors are:\n" <>
        " * black\n" <>
        " * red\n" <>
        " * green\n" <>
        " * yellow\n" <>
        " * blue\n" <>
        " * magenta\n" <>
        " * cyan\n" <>
        " * white\n" <>
        " * brightBlack\n" <>
        " * brightRed\n" <>
        " * brightGreen\n" <>
        " * brightYellow\n" <>
        " * brightBlue\n" <>
        " * brightMagenta\n" <>
        " * brightCyan\n" <>
        " * brightWhite\n" <>
        "  \n" <>
        "Available styles are:\n" <>
        " * standout\n" <>
        " * underline\n" <>
        " * reverseVideo\n" <>
        " * blink\n" <>
        " * dim\n" <>
        " * bold\n" <>
        "  \n" <>
        "In addition, a special value of *default* is possible for either color " <>
        "setting of an attribute. This value indicates that the attribute should " <>
        "use the terminal emulator's default foreground or background color of " <>
        "choice rather than a specific ANSI color."
  , padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Username Highlighting"
  , padTop (Pad 1) $ hCenter $ hLimit 72 $ renderText $
        "Username colors are chosen by hashing each username and then using the hash " <>
        "to choose a color from a list of predefined username colors. If you would like " <>
        "to change the color in a given entry of this list, we provide the " <>
        "\"username.N\" attributes, where N is the index in the username color list."
  , padTop (Pad 1) $ hCenter $ withDefAttr helpEmphAttr $ txt "Theme Attributes"
  , padTop (Pad 1) $ hCenter $ hLimit 72 $ renderText $
        "This section lists all possible theme attributes for use in customization " <>
        "files along with a description of how each one is used in Matterhorn. Each " <>
        "option listed can be set in the *other* section of the customization file. " <>
        "Each provides three customization settings:\n" <>
        " * *<option>.fg = <color>*\n" <>
        " * *<option>.bg = <color>*\n" <>
        " * *<option>.style = <style>* or *<option>.style = [<style>, ...]*\n"

  , padTop (Pad 1) $ hCenter $ hLimit 72 $ renderText $
        let names = sort $
                    (\(n, msg) -> (attrNameToConfig n, msg)) <$>
                    (M.toList $ themeDescriptions themeDocs)
            mkEntry (opt, msg) = "*" <> opt <> "*\n" <> msg <> "\n"
        in T.concat $ mkEntry <$> names
  ]

attrNameToConfig :: AttrName -> T.Text
attrNameToConfig = T.pack . intercalate "." . attrNameComponents

withMargins :: (Int, Int) -> Widget a -> Widget a
withMargins (hMargin, vMargin) w =
    Widget (hSize w) (vSize w) $ do
        ctx <- getContext
        let wl = ctx^.availWidthL - (2 * hMargin)
            hl = ctx^.availHeightL - (2 * vMargin)
        render $ hLimit wl $ vLimit hl w

keybindSections :: KeyConfig -> [(T.Text, [Keybinding])]
keybindSections kc =
    [ ("This Help Page", helpKeybindings kc)
    , ("Main Interface", mainKeybindings kc)
    , ("Channel Select Mode", channelSelectKeybindings kc)
    , ("URL Select Mode", urlSelectKeybindings kc)
    , ("Channel Scroll Mode", channelScrollKeybindings kc)
    , ("Message Select Mode", messageSelectKeybindings kc)
    , ("Text Editing", editingKeybindings)
    , ("Flagged Messages", postListOverlayKeybindings kc)
    , ("User Listings", userListOverlayKeybindings kc)
    ]

helpBox :: Name -> Widget Name -> Widget Name
helpBox n helpText =
    centerLayer $ withMargins (2, 1) $
      (withDefAttr helpAttr $ borderWithLabel (withDefAttr helpEmphAttr $ txt "Matterhorn Help") $
       (viewport HelpViewport Vertical $ cached n helpText)) <=>
      quitMessage
    where
    quitMessage = padTop (Pad 1) $ hCenter $ txt "Press Esc to exit the help screen."

kbColumnWidth :: Int
kbColumnWidth = 12

kbDescColumnWidth :: Int
kbDescColumnWidth = 60

mkKeybindingHelp :: (T.Text, [Keybinding]) -> Widget Name
mkKeybindingHelp (sectionName, kbs) =
    (hCenter $ padTop (Pad 1) $ withDefAttr helpEmphAttr $ txt $ "Keybindings: " <> sectionName) <=>
    (hCenter $ vBox $ mkKeybindHelp <$> (sortWith (ppBinding.eventToBinding.kbEvent) kbs))

mkKeybindHelp :: Keybinding -> Widget Name
mkKeybindHelp (KB desc ev _ _) =
    (withDefAttr helpEmphAttr $ txt $ padTo kbColumnWidth $ ppBinding $ eventToBinding ev) <+>
    (vLimit 1 $ hLimit kbDescColumnWidth $ renderText desc <+> fill ' ')


mkKeybindEventSectionHelp :: (T.Text, [Keybinding]) -> Widget Name
mkKeybindEventSectionHelp (sectionName, kbs) =
  let lst = sortWith (fmap keyEventName . kbBindingInfo . head) $ groupWith kbBindingInfo kbs
  in if all (all (isNothing . kbBindingInfo)) lst
       then emptyWidget
       else (hCenter $ padTop (Pad 1) $ withDefAttr helpEmphAttr $ txt $ "Keybindings: " <> sectionName) <=>
            (hCenter $ vBox $ concat $ mkKeybindEventHelp <$> lst)

mkKeybindEventHelp :: [Keybinding] -> [Widget Name]
mkKeybindEventHelp ks@(KB desc _ _ (Just e):_) =
  let evs = [ ev | KB _ ev _ _ <- ks ]
      evText = T.intercalate ", " (map (ppBinding . eventToBinding) evs)
  in [ txt (padTo 72 ("; " <> desc))
     , (withDefAttr helpEmphAttr $ txt $ keyEventName e) <+>
       txt (" = " <> evText)
     , str " "
     ]
mkKeybindEventHelp _ = []

padTo :: Int -> T.Text -> T.Text
padTo n s = s <> T.replicate (n - T.length s) " "
