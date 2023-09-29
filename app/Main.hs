{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main (main) where

import Control.Monad.Except (
    ExceptT,
    MonadError,
    MonadIO,
    liftEither,
    runExceptT,
    throwError,
 )
import Data.Bifunctor (first)
import Data.ByteString.Char8 qualified as BSC
import Data.Maybe (fromJust, fromMaybe)
import Network.Simple.TCP (HostPreference (Host), Socket, recv, send, serve)
import Parse (ParseError, parseHttpReq)
import Types (
    HttpRequest (..),
    HttpResponse (..),
    StatusCode (..),
    emptyResWithStatus,
    getHeader,
    mkOkRes,
    responseToStr,
 )

bufferSize :: Int
bufferSize = 4096

data HttpServerError = EmptyRequest | MalformedReq ParseError
    deriving (Show)

newtype HttpServer a = HttpServer
    { runHttpServer :: ExceptT HttpServerError IO a
    }
    deriving
        ( Functor
        , Applicative
        , Monad
        , MonadError HttpServerError
        , MonadIO
        )

handleClient :: Socket -> HttpServer ()
handleClient socket = do
    maybeRawReq <- recv socket bufferSize
    rawReq <- maybe (throwError EmptyRequest) pure maybeRawReq
    parsedReq@HttpRequest{..} <- liftEither $ first MalformedReq $ parseHttpReq rawReq
    response <-
        if
                | path == "/" -> pure ok200
                | "/echo/" `BSC.isPrefixOf` path -> pure $ extractPath parsedReq
                | path == "/user-agent" -> pure $ extractHeader parsedReq
                | otherwise -> pure notFound404
    _ <- send socket (responseToStr response)
    pure ()

ok200 :: HttpResponse
ok200 = emptyResWithStatus Ok

notFound404 :: HttpResponse
notFound404 = emptyResWithStatus NotFound

extractPath :: HttpRequest -> HttpResponse
extractPath HttpRequest{..} =
    mkOkRes (fromJust $ BSC.stripPrefix "/echo/" path)

extractHeader :: HttpRequest -> HttpResponse
extractHeader req =
    mkOkRes (fromMaybe "" $ getHeader req "User-Agent")

main :: IO ()
main = do
    let host = "127.0.0.1"
        port = "4221"

    BSC.putStrLn $ "Listening on " <> BSC.pack host <> ":" <> BSC.pack port

    serve (Host host) port $ \(sock, addr) -> do
        BSC.putStrLn $ "Accepted connection from " <> BSC.pack (show addr) <> "."
        errOrRes <- runExceptT (runHttpServer $ handleClient sock)
        case errOrRes of
            Left err -> BSC.putStrLn $ "Error: " <> BSC.pack (show err)
            Right _ -> pure ()
