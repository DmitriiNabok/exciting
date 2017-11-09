<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0"
    xmlns:ex="http://xml.exciting-code.org/inputschemaextentions.xsd"
    xmlns:xs="http://www.w3.org/2001/XMLSchema">
    <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
    <xsl:template match="/">
        <xs:schema xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ex="http://xml.exciting-code.org/inputschemaextentions.xsd"
            xmlns:xs="http://www.w3.org/2001/XMLSchema"
            xsi:schemaLocation="http://xml.exciting-code.org/inputschemaextentions.xsd    http://xml.exciting-code.org/inputschemaextentions.xsd">
            <xsl:comment>
                <xsl:text>
#######################
!DO NOT EDIT THIS FILE!
#######################

This file is compiled form the files in the schema directiory:

input.xsd 
</xsl:text>
                <xsl:for-each select="xs:schema/xs:include">
                    <xsl:value-of select="@schemaLocation"/>
                    <xsl:text> 
</xsl:text>
                </xsl:for-each>
            </xsl:comment>
            <xs:annotation>
                <xs:appinfo>
                    <includes>
                        <xsl:for-each select="xs:schema/xs:include">
                    <xsl:value-of select="@schemaLocation"/> <xsl:text> </xsl:text>
                </xsl:for-each>
                    </includes>
                </xs:appinfo>
            </xs:annotation>
            <xsl:for-each select="xs:schema/xs:include">
                <xsl:variable name="schemaLocation" select="@schemaLocation"/>
                <xsl:copy-of select="document($schemaLocation)/*/*[name()!='xs:include']"/>

            </xsl:for-each>
            <xsl:for-each select="/*/*[name()!='xs:include']">
                <xsl:copy-of select="."/>
            </xsl:for-each>
        </xs:schema>
    </xsl:template>
</xsl:stylesheet>
