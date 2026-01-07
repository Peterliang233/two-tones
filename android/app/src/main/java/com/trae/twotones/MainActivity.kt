package com.trae.twotones

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import com.trae.twotones.ui.theme.TwoTonesTheme

class MainActivity : ComponentActivity() {
    private val gameEngine: GameEngine by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            TwoTonesTheme {
                Surface(color = MaterialTheme.colorScheme.background) {
                    GameView(gameEngine)
                }
            }
        }
    }

    override fun onPause() {
        super.onPause()
        gameEngine.pauseGame()
    }

    override fun onResume() {
        super.onResume()
        gameEngine.resumeGame()
    }
}
