/***************************************************************************
                         qgsexpressionparser.yy
                          --------------------
    begin                : August 2011
    copyright            : (C) 2011 by Martin Dobias
    email                : wonder.sk at gmail dot com
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/

%{
#include <qglobal.h>
#include <QList>
#include <cstdlib>
#include "expression/qgsexpression.h"
#include "expression/qgsexpressionnode.h"
#include "expression/qgsexpressionnodeimpl.h"
#include "expression/qgsexpressionfunction.h"

#ifdef _MSC_VER
#  pragma warning( disable: 4065 )  // switch statement contains 'default' but no 'case' labels
#  pragma warning( disable: 4702 )  // unreachable code
#endif

// don't redeclare malloc/free
#define YYINCLUDED_STDLIB_H 1

struct expression_parser_context;
#include "qgsexpressionparser.hpp"

//! from lexer
typedef void* yyscan_t;
typedef struct yy_buffer_state* YY_BUFFER_STATE;
extern int exp_lex_init(yyscan_t* scanner);
extern int exp_lex_destroy(yyscan_t scanner);
extern int exp_lex(YYSTYPE* yylval_param, YYLTYPE* yyloc, yyscan_t yyscanner);
extern YY_BUFFER_STATE exp__scan_string(const char* buffer, yyscan_t scanner);

/** returns parsed tree, otherwise returns nullptr and sets parserErrorMsg
    (interface function to be called from QgsExpression)
  */
QgsExpressionNode* parseExpression(const QString& str, QString& parserErrorMsg, QgsExpression::ParserError& parserError);

/** error handler for bison */
void exp_error(YYLTYPE* yyloc, expression_parser_context* parser_ctx, const char* msg);

struct expression_parser_context
{
  // lexer context
  yyscan_t flex_scanner;

  // varible where the parser error will be stored
  QString errorMsg;
  QgsExpression::ParserError parserError;
  // root node of the expression
  QgsExpressionNode* rootNode;
};

#define scanner parser_ctx->flex_scanner

// we want verbose error messages
#define YYERROR_VERBOSE 1

#define BINOP(x, y, z)  new QgsExpressionNodeBinaryOperator(x, y, z)

%}

// make the parser reentrant
%locations
%define api.pure
%lex-param {void * scanner}
%parse-param {expression_parser_context* parser_ctx}

%name-prefix "exp_"

%union
{
  QgsExpressionNode* node;
  QgsExpressionNode::NodeList* nodelist;
  QgsExpressionNode::NamedNode* namednode;
  double numberFloat;
  int    numberInt;
  bool   boolVal;
  QString* text;
  QgsExpressionNodeBinaryOperator::BinaryOperator b_op;
  QgsExpressionNodeUnaryOperator::UnaryOperator u_op;
  QgsExpressionNodeCondition::WhenThen* whenthen;
  QgsExpressionNodeCondition::WhenThenList* whenthenlist;
}

%start root


//
// token definitions
//

// operator tokens
%token <b_op> OR AND EQ NE LE GE LT GT REGEXP LIKE IS PLUS MINUS MUL DIV INTDIV MOD CONCAT POW
%token <u_op> NOT
%token IN

// literals
%token <numberFloat> NUMBER_FLOAT
%token <numberInt> NUMBER_INT
%token <boolVal> BOOLEAN
%token NULLVALUE

// tokens for conditional expressions
%token CASE WHEN THEN ELSE END

%token <text> STRING COLUMN_REF FUNCTION SPECIAL_COL VARIABLE NAMED_NODE

%token COMMA

%token Unknown_CHARACTER

//
// definition of non-terminal types
//

%type <node> expression
%type <nodelist> exp_list
%type <whenthen> when_then_clause
%type <whenthenlist> when_then_clauses
%type <namednode> named_node

// debugging
%error-verbose

//
// operator precedence
//

// left associativity means that 1+2+3 translates to (1+2)+3
// the order of operators here determines their precedence

%left OR
%left AND
%right NOT
%left EQ NE LE GE LT GT REGEXP LIKE IS IN
%left PLUS MINUS
%left MUL DIV INTDIV MOD
%right POW
%left CONCAT

%right UMINUS  // fictitious symbol (for unary minus)

%left COMMA

%destructor { delete $$; } <node>
%destructor { delete $$; } <nodelist>
%destructor { delete $$; } <namednode>
%destructor { delete $$; } <text>
%destructor { delete $$; } <whenthen>
%destructor { delete $$; } <whenthenlist>

%%

root: expression { parser_ctx->rootNode = $1; }
   ;

expression:
      expression AND expression       { $$ = BINOP($2, $1, $3); }
    | expression OR expression        { $$ = BINOP($2, $1, $3); }
    | expression EQ expression        { $$ = BINOP($2, $1, $3); }
    | expression NE expression        { $$ = BINOP($2, $1, $3); }
    | expression LE expression        { $$ = BINOP($2, $1, $3); }
    | expression GE expression        { $$ = BINOP($2, $1, $3); }
    | expression LT expression        { $$ = BINOP($2, $1, $3); }
    | expression GT expression        { $$ = BINOP($2, $1, $3); }
    | expression REGEXP expression    { $$ = BINOP($2, $1, $3); }
    | expression LIKE expression      { $$ = BINOP($2, $1, $3); }
    | expression IS expression        { $$ = BINOP($2, $1, $3); }
    | expression PLUS expression      { $$ = BINOP($2, $1, $3); }
    | expression MINUS expression     { $$ = BINOP($2, $1, $3); }
    | expression MUL expression       { $$ = BINOP($2, $1, $3); }
    | expression INTDIV expression    { $$ = BINOP($2, $1, $3); }
    | expression DIV expression       { $$ = BINOP($2, $1, $3); }
    | expression MOD expression       { $$ = BINOP($2, $1, $3); }
    | expression POW expression       { $$ = BINOP($2, $1, $3); }
    | expression CONCAT expression    { $$ = BINOP($2, $1, $3); }
    | NOT expression                  { $$ = new QgsExpressionNodeUnaryOperator($1, $2); }
    | '(' expression ')'              { $$ = $2; }
    | FUNCTION '(' exp_list ')'
        {
          int fnIndex = QgsExpression::functionIndex(*$1);
          delete $1;
          if (fnIndex == -1)
          {
            // this should not actually happen because already in lexer we check whether an identifier is a known function
            // (if the name is not known the token is parsed as a column)
            QgsExpression::ParserError::ParserErrorType errorType = QgsExpression::ParserError::FunctionUnknown;
            parser_ctx->parserError.errorType = errorType;
            exp_error(&yyloc, parser_ctx, "Function is not known");
            delete $3;
            YYERROR;
          }
          QString paramError;
          if ( !QgsExpressionNodeFunction::validateParams( fnIndex, $3, paramError ) )
          {
            QgsExpression::ParserError::ParserErrorType errorType = QgsExpression::ParserError::FunctionInvalidParams;
            parser_ctx->parserError.errorType = errorType;
            exp_error( &yyloc, parser_ctx, paramError.toLocal8Bit().constData() );
            delete $3;
            YYERROR;
          }
          if ( QgsExpression::Functions()[fnIndex]->params() != -1
               && !( QgsExpression::Functions()[fnIndex]->params() >= $3->count()
               && QgsExpression::Functions()[fnIndex]->minParams() <= $3->count() ) )
          {
            QgsExpression::ParserError::ParserErrorType errorType = QgsExpression::ParserError::FunctionWrongArgs;
            parser_ctx->parserError.errorType = errorType;
            exp_error(&yyloc, parser_ctx, QString( "%1 function is called with wrong number of arguments" ).arg( QgsExpression::Functions()[fnIndex]->name() ).toLocal8Bit().constData() );
            delete $3;
            YYERROR;
          }
          $$ = new QgsExpressionNodeFunction(fnIndex, $3);
        }

    | FUNCTION '(' ')'
        {
          int fnIndex = QgsExpression::functionIndex(*$1);
          delete $1;
          if (fnIndex == -1)
          {
            // this should not actually happen because already in lexer we check whether an identifier is a known function
            // (if the name is not known the token is parsed as a column)
            QgsExpression::ParserError::ParserErrorType errorType = QgsExpression::ParserError::FunctionUnknown;
            parser_ctx->parserError.errorType = errorType;
            exp_error(&yyloc, parser_ctx, "Function is not known");
            YYERROR;
          }
          // 0 parameters is expected, -1 parameters means leave it to the
          // implementation
          if ( QgsExpression::Functions()[fnIndex]->params() > 0 )
          {
            QgsExpression::ParserError::ParserErrorType errorType = QgsExpression::ParserError::FunctionWrongArgs;
            parser_ctx->parserError.errorType = errorType;
            exp_error(&yyloc, parser_ctx, QString( "%1 function is called with wrong number of arguments" ).arg( QgsExpression::Functions()[fnIndex]->name() ).toLocal8Bit().constData() );
            YYERROR;
          }
          $$ = new QgsExpressionNodeFunction(fnIndex, new QgsExpressionNode::NodeList());
        }

    | expression IN '(' exp_list ')'     { $$ = new QgsExpressionNodeInOperator($1, $4, false);  }
    | expression NOT IN '(' exp_list ')' { $$ = new QgsExpressionNodeInOperator($1, $5, true); }

    | PLUS expression %prec UMINUS { $$ = $2; }
    | MINUS expression %prec UMINUS { $$ = new QgsExpressionNodeUnaryOperator( QgsExpressionNodeUnaryOperator::uoMinus, $2); }

    | CASE when_then_clauses END      { $$ = new QgsExpressionNodeCondition($2); }
    | CASE when_then_clauses ELSE expression END  { $$ = new QgsExpressionNodeCondition($2,$4); }

    // columns
    | COLUMN_REF                  { $$ = new QgsExpressionNodeColumnRef( *$1 ); delete $1; }

    // special columns (actually functions with no arguments)
    | SPECIAL_COL
        {
          int fnIndex = QgsExpression::functionIndex(*$1);
          if (fnIndex >= 0)
          {
            $$ = new QgsExpressionNodeFunction( fnIndex, nullptr );
          }
          else
          {
            QgsExpression::ParserError::ParserErrorType errorType = QgsExpression::ParserError::FunctionUnknown;
            parser_ctx->parserError.errorType = errorType;
            exp_error(&yyloc, parser_ctx, QString("%1 function is not known").arg(*$1).toLocal8Bit().constData());
            YYERROR;
          }
          delete $1;
        }

    // variables
    | VARIABLE
        {
          // @var is equivalent to var( "var" )
          QgsExpressionNode::NodeList* args = new QgsExpressionNode::NodeList();
          QgsExpressionNodeLiteral* literal = new QgsExpressionNodeLiteral( QString(*$1).mid(1) );
          args->append( literal );
          $$ = new QgsExpressionNodeFunction( QgsExpression::functionIndex( "var" ), args );
          delete $1;
        }

    //  literals
    | NUMBER_FLOAT                { $$ = new QgsExpressionNodeLiteral( QVariant($1) ); }
    | NUMBER_INT                  { $$ = new QgsExpressionNodeLiteral( QVariant($1) ); }
    | BOOLEAN                     { $$ = new QgsExpressionNodeLiteral( QVariant($1) ); }
    | STRING                      { $$ = new QgsExpressionNodeLiteral( QVariant(*$1) ); delete $1; }
    | NULLVALUE                   { $$ = new QgsExpressionNodeLiteral( QVariant() ); }
;

named_node:
    NAMED_NODE expression { $$ = new QgsExpressionNode::NamedNode( *$1, $2 ); delete $1; }
   ;

exp_list:
      exp_list COMMA expression
       {
         if ( $1->hasNamedNodes() )
         {
           QgsExpression::ParserError::ParserErrorType errorType = QgsExpression::ParserError::FunctionNamedArgsError;
           parser_ctx->parserError.errorType = errorType;
           exp_error(&yyloc, parser_ctx, "All parameters following a named parameter must also be named.");
           delete $1;
           YYERROR;
         }
         else
         {
           $$ = $1; $1->append($3);
         }
       }
    | exp_list COMMA named_node { $$ = $1; $1->append($3); }
    | expression              { $$ = new QgsExpressionNode::NodeList(); $$->append($1); }
    | named_node              { $$ = new QgsExpressionNode::NodeList(); $$->append($1); }
   ;

when_then_clauses:
      when_then_clauses when_then_clause  { $$ = $1; $1->append($2); }
    | when_then_clause                    { $$ = new QgsExpressionNodeCondition::WhenThenList(); $$->append($1); }
   ;

when_then_clause:
      WHEN expression THEN expression     { $$ = new QgsExpressionNodeCondition::WhenThen($2,$4); }
   ;

%%


// returns parsed tree, otherwise returns nullptr and sets parserErrorMsg
QgsExpressionNode* parseExpression(const QString& str, QString& parserErrorMsg, QgsExpression::ParserError &parserError)
{
  expression_parser_context ctx;
  ctx.rootNode = 0;

  exp_lex_init(&ctx.flex_scanner);
  exp__scan_string(str.toUtf8().constData(), ctx.flex_scanner);
  int res = exp_parse(&ctx);
  exp_lex_destroy(ctx.flex_scanner);

  // list should be empty when parsing was OK
  if (res == 0) // success?
  {
    return ctx.rootNode;
  }
  else // error?
  {
    parserErrorMsg = ctx.errorMsg;
    parserError = ctx.parserError;
    delete ctx.rootNode;
    return nullptr;
  }
}


void exp_error(YYLTYPE* yyloc,expression_parser_context* parser_ctx, const char* msg)
{
  parser_ctx->errorMsg = msg;
  parser_ctx->parserError.firstColumn = yyloc->first_column;
  parser_ctx->parserError.firstLine = yyloc->first_line;
  parser_ctx->parserError.lastColumn = yyloc->last_column;
  parser_ctx->parserError.lastLine = yyloc->last_line;
}
