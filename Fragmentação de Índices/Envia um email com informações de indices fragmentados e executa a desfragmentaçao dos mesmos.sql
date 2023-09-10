---------------------------------------------------------------------------

--GitHub -> https://github.com/Denner-Maia
--Linkedin -> linkedin.com/in/denner-maia-664b35164
--email -> dennermaia22@gmail.com


--O Script asseguir verifica se h� indices fragmentados no seu BD, caso h�ja � feito o envio de um email para o DBA 
--informando os indices fragmentados e ao mesmo tempo
--executa uma proc para a desfragmenta��o dos indices encontrados.

--Meu intuito ao desenvolver esse script e estar sempre deixando o DBA informado dos indices que se fragmentam
--e automatizando a desfragmenta�ao dos indices

--O email enviado informando indice, tabela, schema e nivel de fragmenta�ao � formatado em HTML e CSS tendo uma
--informa�ao visual bem mais intuitiva.

--Utilizei como referencia o post do Dirceu Rezende para a cria�ao do script para envio do email, segue o Link
--https://www.dirceuresende.com/blog/como-habilitar-enviar-monitorar-emails-pelo-sql-server-sp_send_dbmail/
----------------------------------------------------------------------------


----------------------------------------------------------------
--#Instru��o Passo 1
--Primeiro criamos a Procedure para executar a desfragmenta�ao do BD
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
--#Instru��o Passo 2
--Criar a Procedure que envia o email ao DBA e executa a procedure de desfragmenta��o criada no passo 1
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
O processo de desfragmenta��o dos indices j� est� em andamento!,<br/>'

;


-- Envia o e-mail
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'Perfil do DatabaseMail', -- sysname
    @recipients = 'email que ir� receber a informa��o', -- varchar(max)
    @subject = N'Indices Fragmentados', -- nvarchar(255)
    @body = @HTML, -- nvarchar(max)
    @body_format = 'html'

	--Executando a Procedure para desfragmenta�ao dos Indices 
	exec sp_desfragmentar_indices;
GO

-----------------------------------------------------------
--#Instru��o Passo 3 (Opcional)
--Criar o job conforme hor�rio ou dia dispon�vel no seu BD 


--Verifica se existe indices fragmentados no seu BD.
IF EXISTS
(SELECT 
	avg_fragmentation_in_percent	
	
FROM sys.dm_db_index_physical_stats(DB_ID('FabricioLimaConsultoria'),OBJECT_ID('TestesIndices'),NULL,NULL,null)
	WHERE avg_fragmentation_in_percent > 5
	AND page_count > 1000
)
--Caso encontre indices fragmentados envia o email ao DBA e executa a procedure de desfragmenta�ao. 
	exec sp_enviar_email_de_indices_fragmentados
go
