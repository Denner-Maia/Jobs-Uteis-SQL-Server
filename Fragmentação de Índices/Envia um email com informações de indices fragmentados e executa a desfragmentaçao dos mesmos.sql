---------------------------------------------------------------------------

--GitHub -> https://github.com/Denner-Maia
--Linkedin -> linkedin.com/in/denner-maia-664b35164
--email -> dennermaia22@gmail.com


--O Script asseguir verifica se há indices fragmentados no seu BD, caso hája é feito o envio de um email para o DBA 
--informando os indices fragmentados e ao mesmo tempo
--executa uma proc para a desfragmentação dos indices encontrados.

--Meu intuito ao desenvolver esse script e estar sempre deixando o DBA informado dos indices que se fragmentam
--e automatizando a desfragmentaçao dos indices

--O email enviado informando indice, tabela, schema e nivel de fragmentaçao é formatado em HTML e CSS tendo uma
--informaçao visual bem mais intuitiva.

--Utilizei como referencia o post do Dirceu Rezende para a criaçao do script para envio do email, segue o Link
--https://www.dirceuresende.com/blog/como-habilitar-enviar-monitorar-emails-pelo-sql-server-sp_send_dbmail/
----------------------------------------------------------------------------


----------------------------------------------------------------
--#Instrução Passo 1
--Primeiro criamos a Procedure para executar a desfragmentaçao do BD
--Obs.: informar o nome do BD que deseja criar o proc. 

USE 'Nome do BD'
GO

CREATE PROCEDURE sp_desfragmentar_indices
AS 

SELECT
	D.NAME AS INDICE,
	C.NAME AS SCHEM,
	B.NAME AS TAB,
	A.AVG_FRAGMENTATION_IN_PERCENT AS FRAG, 
	A.PAGE_COUNT AS NUM_PAGINAS
	INTO #FRAGMENTACAO
FROM SYS.DM_DB_INDEX_PHYSICAL_STATS (DB_ID(), NULL, NULL, NULL, NULL) AS A
INNER JOIN SYS.TABLES B 
     ON B.[OBJECT_ID] = A.[OBJECT_ID]
INNER JOIN SYS.SCHEMAS C 
     ON B.[SCHEMA_ID] = C.[SCHEMA_ID]
INNER JOIN SYS.INDEXES AS D 
     ON D.[OBJECT_ID] = A.[OBJECT_ID]
	AND A.INDEX_ID = D.INDEX_ID
WHERE A.DATABASE_ID = DB_ID()
AND A.AVG_FRAGMENTATION_IN_PERCENT >5
AND D.[NAME]  IS NOT NULL
AND A.PAGE_COUNT > 1000

DECLARE @SQLCMD VARCHAR(200) = ''
DECLARE @NAMEIND VARCHAR(100) = ''
while exists (select * from #FRAGMENTACAO)
begin
	select top 1 @NAMEIND = INDICE,
		@SQLCMD = 'ALTER INDEX ' + INDICE + ' ON ' + SCHEM + '.' + TAB + CASE WHEN FRAG > 5 AND FRAG < 30 THEN ' REORGANIZE;'
						ELSE ' REBUILD;' END
	from #FRAGMENTACAO 
	DELETE #FRAGMENTACAO WHERE INDICE = @NAMEIND
	EXEC(@SQLCMD)
	--PRINT(@SQLCMD)
end
drop table #FRAGMENTACAO
GO

-----------------------------------------------------------
--#Instrução Passo 2
--Criar a Procedure que envia o email ao DBA e executa a procedure de desfragmentação criada no passo 1
--Inserir o perfil do Databasemail que esta configurado na sua maquina
--inserir o endereco de email que irá receber o email
	
--Obs.: informar o nome do BD que deseja criar a proc. 

USE 'Nome do BD'
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

create procedure sp_enviar_email_de_indices_fragmentados
as 
DECLARE  @HTML VARCHAR(MAX)

SET @HTML = '
<html>
<head>
    <title>Titulo</title>
    <style type="text/css">
        table { padding:0; border-spacing: 0; border-collapse: collapse; }
        thead { background: #0064b0; border: 1px solid #ddd; }
        th { padding: 10px; font-weight: bold; border: 1px solid #000; color: #fff; }
        tr { padding: 0; }
        td { padding: 5px; border: 1px solid #cacaca; margin:0; text-align: center; }
    </style>
</head>



<table>
    <thead>
        <tr>
            <th>INDICE</th>
            <th>SCHEM</th>
            <th>TAB</th>
			<th>FRAG</th>
			<th>NUM_PAGINAS</th>
        </tr>
    </thead>
    
    <tbody>' +  
    CAST ( 
    (
        SELECT 
		td = D.NAME, '',
       td = C.NAME, '',
       td = B.NAME, '',
       td = A.AVG_FRAGMENTATION_IN_PERCENT, '',
       td = A.PAGE_COUNT,''
FROM SYS.DM_DB_INDEX_PHYSICAL_STATS (DB_ID(), NULL, NULL, NULL, NULL) AS A
INNER JOIN SYS.TABLES B ON B.[OBJECT_ID] = A.[OBJECT_ID]
INNER JOIN SYS.SCHEMAS C ON B.[SCHEMA_ID] = C.[SCHEMA_ID]
INNER JOIN SYS.INDEXES AS D ON D.[OBJECT_ID] = A.[OBJECT_ID]
AND A.INDEX_ID = D.INDEX_ID
WHERE A.DATABASE_ID = DB_ID()
  AND A.AVG_FRAGMENTATION_IN_PERCENT >5
  AND D.[NAME] IS NOT NULL
  AND A.PAGE_COUNT > 1000
        FOR XML PATH('tr'), TYPE
    ) AS NVARCHAR(MAX) ) + '
    </tbody>
</table>
<br/><br/>
O processo de desfragmentação dos indices já está em andamento!,<br/>'

;


-- Envia o e-mail
--Inserir o perfil do Databasemail que esta configurado na sua maquina
--inserir o endereco de email que irá receber o email

EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'Perfil do DatabaseMail', -- sysname
    @recipients = 'email que irá receber a informação', -- varchar(max)
    @subject = N'Indices Fragmentados', -- nvarchar(255)
    @body = @HTML, -- nvarchar(max)
    @body_format = 'html'

	--Executando a Procedure para desfragmentaçao dos Indices 
	exec sp_desfragmentar_indices;
GO

-----------------------------------------------------------
--#Instrução Passo 3 (Opcional)
--Criar o job conforme horário ou dia disponível no seu BD 


--Verifica se existe indices fragmentados no seu BD.
IF EXISTS
(SELECT 
	avg_fragmentation_in_percent	
	
FROM sys.dm_db_index_physical_stats(DB_ID('FabricioLimaConsultoria'),OBJECT_ID('TestesIndices'),NULL,NULL,null)
	WHERE avg_fragmentation_in_percent > 5
	AND page_count > 1000
)
--Caso encontre indices fragmentados envia o email ao DBA e executa a procedure de desfragmentaçao. 
	exec sp_enviar_email_de_indices_fragmentados
go
