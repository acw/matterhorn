{-# LANGUAGE RecordWildCards #-}

module Config
  ( Config(..)
  , PasswordSource(..)
  , findConfig
  ) where

import           Control.Exception
import           Control.Monad.Trans.Except
import           Control.Monad.IO.Class
import qualified Data.HashMap.Strict as HM
import           Data.Ini
import           Data.Text (Text)
import qualified Data.Text as T
import           Data.Monoid ((<>))
import           System.Directory (doesFileExist)
import           System.Environment.XDG.BaseDir (getAllConfigFiles)
import           System.IO.Error (ioeGetErrorString)
import           System.Process (readProcess)

data PasswordSource =
    PasswordString Text
    | PasswordCommand String
    deriving (Eq, Read, Show)

data Config = Config
  { configUser     :: Text
  , configHost     :: Text
  , configTeam     :: Text
  , configPort     :: Int
  , configPass     :: PasswordSource
  } deriving (Eq, Show)

(??) :: Maybe a -> String -> Either String a
(Just x) ?? _ = Right x
Nothing  ?? s = Left ("Missing field: `" ++ s ++ "`")

readT :: Read a => Text -> a
readT = read . T.unpack

fromIni :: Ini -> Either String Config
fromIni (Ini ini) = do
  cS <- HM.lookup "mattermost" ini ?? "mattermost"
  configUser <- HM.lookup "user" cS ?? "user"
  configHost <- HM.lookup "host" cS ?? "host"
  configTeam <- HM.lookup "team" cS ?? "team"
  configPort <- readT `fmap` (HM.lookup "port" cS ?? "port")
  let passCmd = HM.lookup "passcmd" cS
  let pass    = HM.lookup "pass" cS
  configPass <- case passCmd of
    Nothing -> case pass of
      Nothing -> fail "Either `pass` or `passcmd` is needed."
      Just p -> return (PasswordString p)
    Just c -> return (PasswordCommand (T.unpack c))
  return Config { .. }

findConfig :: IO (Either String Config)
findConfig = do
  xdgLocations <- getAllConfigFiles "matterhorn" "config.ini"
  let confLocations = ["./config.ini"] ++ xdgLocations
                                       ++ ["/etc/matterhorn/config.ini"]
  loop confLocations
  where loop [] = return $ Left "No matterhorn configuration found"
        loop (c:cs) = do
          ex <- doesFileExist c
          if ex
            then getConfig c
            else loop cs

getConfig :: FilePath -> IO (Either String Config)
getConfig fp = runExceptT $ do
  t <- liftIO $ readIniFile fp
  case t >>= fromIni of
    Left err -> do
      throwE $ "Unable to parse " ++ fp ++ ":" ++ err
    Right conf -> do
      actualPass <- case configPass conf of
        PasswordCommand cmdString -> do
          let (cmd:rest) = words cmdString
          output <- convertIOException (readProcess cmd rest "") `catchE`
                    (\e -> throwE $ "Could not execute password command: " <> e)
          return $ T.pack (takeWhile (/= '\n') output)
        PasswordString pass -> return pass
      return conf { configPass = PasswordString actualPass }

convertIOException :: IO a -> ExceptT String IO a
convertIOException act = do
    result <- liftIO $ (Right <$> act) `catch`
                       (\(e::IOError) -> return $ Left $ ioeGetErrorString e)
    case result of
        Left e -> throwE e
        Right v -> return v
