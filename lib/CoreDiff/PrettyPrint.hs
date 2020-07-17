{-# LANGUAGE OverloadedStrings #-}

module CoreDiff.PrettyPrint where

import Data.Maybe
import Data.List
import GhcDump.Ast
import qualified Data.Text as T

import CoreDiff.Diff

prettyPrint :: Show mv => BindingC mv -> String
prettyPrint (BindingC bndr expr) =
  intercalate "\n" $
    [ prettyPrintBndr True bndr
    , prettyPrintBndrInfo bndr
    , prettyPrintBndr False bndr ++ " ="
    , indent 2 (prettyPrintExpr expr)
    ]
prettyPrint (BindingHole hole) = "#" ++ show hole

-- TODO: look at GhcDump/Convert.hs to achieve close-to-original output
prettyPrintBndrInfo (BndrC (SBndr bndr)) = "[" ++ intercalate ", " (catMaybes infos) ++ "]"
  where
    infos =
      [ arity
      , strictness
      , occurences
      ]

    arity =
      if idiArity bInfo == 0
      then Nothing
      else Just $ "Arity=" ++ show (idiArity bInfo)

    strictness =
      toMaybe (idiStrictnessSig bInfo /= "") ("Str=" ++ T.unpack (idiStrictnessSig bInfo))

    occurences = Just $ "Occ=" ++ show' (idiOccInfo bInfo)
      where show' OccManyOccs        = "Many"
            show' OccDead            = "Dead"
            show' OccOneOcc          = "Once"
            show' (OccLoopBreaker _) = "LoopBreaker" -- TODO: show strong/weak loopbreaker (?)

    bInfo = binderIdInfo bndr
    toMaybe test payload
      | test      = Just payload
      | otherwise = Nothing

prettyPrintBndr :: Show mv => Bool -> BndrC mv -> String
prettyPrintBndr displayType (BndrC bndr) = showBndr displayType bndr

prettyPrintBndr _ (BndrHole hole) = "#" ++ show hole

showBndr :: Bool -> SBinder -> String
showBndr displayType (SBndr bndr) =
  T.unpack (binderName bndr) ++ "_" ++ showBndrId (binderId bndr) ++ optType
  where showBndrId (BinderId bndrId) = show bndrId
        optType = if displayType then " :: " ++ prettyPrintType (binderType bndr)
                                 else ""

prettyPrintExpr :: Show mv => ExprC mv -> String
prettyPrintExpr (EVarC bndrId) = show bndrId
prettyPrintExpr (EVarGlobalC extName) = prettyPrintExtName extName
prettyPrintExpr (ELitC lit) = show lit
prettyPrintExpr (EAppC f x) = -- TODO: Type applications
  parensIf (not $ isApp f) (prettyPrintExpr f) ++ " " ++ parensIf (isApp x) (prettyPrintExpr x)
  where
    isApp (EAppC _ _) = True
    isApp _           = False
prettyPrintExpr (ETyLamC param body) =
  "\\@" ++ prettyPrintBndr False param ++ " ->\n" ++ indent 2 (prettyPrintExpr body)
prettyPrintExpr (ELamC param body) =
  "\\" ++ prettyPrintBndr True param ++ " ->\n" ++ indent 2 (prettyPrintExpr body)
prettyPrintExpr (ELetC bindings expr) =
  "let\n" ++ indent 2 (intercalate "\n" $ map prettyPrint bindings) ++ "\nin\n" ++ prettyPrintExpr expr
prettyPrintExpr (ECaseC match _ alts) =
  "case " ++ prettyPrintExpr match ++ " of\n" ++ indent 2 (intercalate "\n" $ map prettyPrintAlt alts)
prettyPrintExpr (ETypeC ty) = prettyPrintType ty
prettyPrintExpr ECoercionC = error "unimplemented"
prettyPrintExpr (ExprHole hole) = "#" ++ show hole

prettyPrintAlt = undefined

prettyPrintType (VarTy bndrId) = show bndrId
prettyPrintType (FunTy lhs rhs) =
  parensIf (isFunTy lhs) (prettyPrintType lhs) ++ " -> " ++ parensIf (not $ isFunTy rhs) (prettyPrintType rhs)
  where
    isFunTy (FunTy _ _) = True
    isFunTy _           = False
prettyPrintType (TyConApp (TyCon tcName _tcUnique) args) =
  T.unpack tcName ++ optArgs
  where
    optArgs = if length args == 0 then ""
                                  else " " ++ intercalate "\n" (map go args)
    go arg = "(" ++ prettyPrintType arg ++ ")"
prettyPrintType (AppTy _ _) = error "unimplemented"
prettyPrintType (ForAllTy bndr ty) = "forall {" ++ showBndr False bndr ++ "}." ++ prettyPrintType ty
prettyPrintType LitTy = error "unimplemented"
prettyPrintType CoercionTy = error "unimplemented"

instance Show ChangeBinding where
  show (ChangeBinding (lhs, rhs)) =
    "(" ++ red (prettyPrint lhs) ++ "/" ++ green (prettyPrint rhs) ++ ")"
    where red = ansiColor 31
          green = ansiColor 32
          ansiColor code str =
            "\ESC[" ++ show code ++ "m" ++ str ++ "\ESC[0m"

-- terminals

prettyPrintExtName extName =
  T.unpack (getModuleName $ externalModuleName extName) ++ "." ++ T.unpack (externalName extName)

-- utilities

indent :: Int -> String -> String
indent n = unlines . map go . lines 
  where go str = replicate n ' ' ++ str

parensIf True str = "(" ++ str ++")"
parensIf False str = str
