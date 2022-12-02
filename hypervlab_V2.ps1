[xml]$XAMLMain = @'
<Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Local Hyper-V LAB" Height="480" Width="640">
    <Grid>
        <TextBox HorizontalAlignment="Left "Height="22" Margin="20,22,0,0" TextWrapping="Wrap" Text="Select your LAB type" VerticalAlignment="Top" Width="140" IsEnabled="False" SelectionOpacity="0" />
        <ComboBox x:Name="LAB_selector" HorizontalAlignment="Left" Margin="180,20,0,0" VerticalAlignment="Top" Width="420" Cursor="Hand" />
        <Border x:Name="Textbox_Frame" BorderBrush="Black" BorderThickness="1" HorizontalAlignment="Center" Margin="0,50,0,100" Width="580">
            <TextBox x:Name="Textbox" HorizontalAlignment="Center" Height="260" TextWrapping="Wrap" Text="" VerticalAlignment="Top" Width="560" Margin="0,10,0,0" IsEnabled="False"/>
        </Border>
        <Button x:Name="Close" Content="Close" HorizontalAlignment="Left" Margin="20,360,0,0" VerticalAlignment="Top" Height="40" Width="120" IsCancel="True" />
        <Button x:Name="Execute" Content="Execute" HorizontalAlignment="Left" Margin="480,360,0,0" VerticalAlignment="Top" Height="40" Width="120"/>

    </Grid>
</Window>
'@
$reader=(New-Object System.Xml.XmlNodeReader $XAMLMain)
$windowMain=[Windows.Markup.XamlReader]::Load( $reader )

$windowMain.ShowDialog() | out-null